// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Network
import Synchronization
import AppData
import RFMedia

/// Media in the chat: receive (policy, import, preview), send (normalise, stage, upload) and the
/// device permission hand-offs. Imports run in the repository; this layer only decides when.
extension ChatViewModel {
    func handleMedia(_ action: ChatAction) {
        switch action {
        case .mediaTapped(let id): tapped(id)
        case .revealMedia(let id): state.revealed.insert(id)
        case .cancelMedia(let id):
            guard let attachment = attachment(id) else { return }
            mediaTasks[id]?.cancel(); mediaTasks[id] = nil
            state.media[id] = .idle
            Task { [repository, account] in await repository.cancelDownload(account: account, attachment: attachment) }
        case .closePreview: state.preview = nil; state.photoSaved = nil
        case .saveToPhotos(let id):
            guard case .ready(let url)? = state.media[id], attachment(id)?.kind == .image || attachment(id)?.kind == .animated else { return }
            pendingSave = url; state.photoSaved = nil
            emit(.requestPermission(.photoAdd))
        case .attachRequested: state.attachSheet = true
        case .closeAttach: state.attachSheet = false
        case .cameraRequested: state.attachSheet = false; emit(.requestPermission(.camera))
        case .permissionResolved(let permission, let granted):
            switch permission {
            case .camera: state.cameraActive = granted
            case .photoAdd:
                guard let url = pendingSave else { return }
                pendingSave = nil
                if granted { savePhoto(url) } else { state.photoSaved = false }
            default: break
            }
        case .photoSaved(let saved): state.photoSaved = saved
        case .attachPicked(let picked): state.attachSheet = false; state.cameraActive = false; stage(picked)
        case .retryMediaSend: if let pending = state.mediaSend { upload(pending) }
        case .discardMediaSend:
            guard let pending = state.mediaSend, pending.failure != nil else { return }
            for item in pending.items { try? FileManager.default.removeItem(at: item.file) }
            state.mediaSend = nil
        default: break
        }
    }

    func stopMedia(conceal: Bool) {
        for task in mediaTasks.values { task.cancel() }
        mediaTasks = [:]; trust = nil; pendingSave = nil
        state.media = [:]; state.revealed = []; state.preview = nil; state.attachSheet = false; state.cameraActive = false; state.photoSaved = nil
        if conceal { ImagePipeline.shared.purge() }
    }

    private func attachment(_ id: String) -> AttachmentRecord? {
        for message in state.messages { if let found = message.attachments.first(where: { $0.id == id }) { return found } }
        return nil
    }

    /// Reconciles transfer states with the window: drops states of attachments that left it,
    /// reads stored originals for new ones and starts the downloads the policy allows.
    func syncMedia() {
        var present: [String: AttachmentRecord] = [:]
        var owners: [String: Bool] = [:]
        for message in state.messages where message.kind != .deleted {
            for item in message.attachments { present[item.id] = item; owners[item.id] = message.isOwn == true }
        }
        for id in state.media.keys where present[id] == nil { state.media[id] = nil; mediaTasks[id]?.cancel(); mediaTasks[id] = nil }
        let fresh = present.values.filter { state.media[$0.id] == nil && mediaTasks[$0.id] == nil }
        guard !fresh.isEmpty else { return }
        let current = epoch
        for item in fresh { state.media[item.id] = item.isExpired(now: now()) ? .expired : .idle }
        let key = "sync:" + String(fresh.count) + ":" + (fresh.first?.id ?? "")
        mediaTasks[key] = Task { [weak self, repository, account] in
            var known: [String: MediaTransferState] = [:]
            for item in fresh { if let stored = await repository.mediaState(account: account, attachment: item) { known[item.id] = stored } }
            guard let self, self.epoch == current else { return }
            self.mediaTasks[key] = nil
            let sender = await self.resolveTrust()
            guard self.epoch == current else { return }
            let network = self.network()
            for item in fresh {
                if let stored = known[item.id] { self.state.media[item.id] = stored; continue }
                guard self.state.media[item.id] == .idle else { continue }
                let own = owners[item.id] == true
                if !own && sender == .untrusted { self.state.media[item.id] = .blockedByPolicy; continue }
                if own || MediaPolicy.autoDownload(item, sender: sender, network: network) { self.download(item) }
            }
        }
    }

    /// Contacts, groups and everyone else. A direct peer counts as a contact only when the
    /// details lookup matches a contact by root commitment; otherwise media stays behind a tap.
    private func resolveTrust() async -> MediaPolicy.Sender {
        if let trust { return trust }
        if state.isGroup { trust = .group; return .group }
        let anchor = state.messages.first { $0.isOwn == false && $0.authorAnchor != nil }?.authorAnchor
        guard let anchor else { return .untrusted }
        let result = await repository.details(account: account, conversation: conversation, peerAnchor: anchor)
        let resolved: MediaPolicy.Sender = if case .success(let details) = result, details.peerPrincipal != nil { .contact } else { .untrusted }
        trust = resolved
        return resolved
    }

    private func tapped(_ id: String) {
        guard let item = attachment(id) else { return }
        switch state.media[id] {
        case .ready(let url)?:
            state.preview = MediaPreview(attachmentID: id, file: url, isImage: (item.kind == .image || item.kind == .animated) && MediaSniffer.format(of: url).isImage)
        case .idle?, .blockedByPolicy?, nil:
            state.revealed.insert(id); download(item)
        case .failed(_, let retryable)? where retryable:
            download(item)
        default: break
        }
    }

    private func download(_ item: AttachmentRecord) {
        guard mediaTasks[item.id] == nil else { return }
        state.media[item.id] = .downloading
        let current = epoch
        mediaTasks[item.id] = Task { [weak self, repository, account] in
            let result = await repository.download(account: account, attachment: item)
            guard let self, self.epoch == current, !Task.isCancelled else { return }
            self.mediaTasks[item.id] = nil
            self.state.media[item.id] = result
        }
    }

    // MARK: Send

    /// Photos are normalised (metadata stripped, 2,560 px, JPEG 0.82); files keep their exact
    /// bytes. Both are staged in the protected outbox before anything reaches the SDK.
    private func stage(_ picked: [PickedMedia]) {
        guard !picked.isEmpty, state.mediaSend == nil else { for item in picked { try? FileManager.default.removeItem(at: item.url) }; return }
        let current = epoch
        let operationID = UUID().uuidString
        mediaTasks["send"] = Task { [weak self, repository, account] in
            guard let outbox = await repository.mediaOutbox(account: account) else {
                for item in picked { try? FileManager.default.removeItem(at: item.url) }
                guard let self, self.epoch == current else { return }
                self.state.failure = repository.unavailable(.attachmentTransfer); self.mediaTasks["send"] = nil
                return
            }
            let staged = await Task.detached { () -> Result<[MediaUpload], AppFailure> in
                var uploads: [MediaUpload] = []
                defer { for item in picked { try? FileManager.default.removeItem(at: item.url) } }
                for item in picked.prefix(16) {
                    do {
                        switch item.kind {
                        case .photo:
                            let result = try ImageNormalizer.normalize(source: item.url, into: outbox)
                            uploads.append(MediaUpload(file: result.file, fileName: result.fileName, mime: result.mime))
                        case .file:
                            let target = outbox.appendingPathComponent(UUID().uuidString)
                            try FileManager.default.copyItem(at: item.url, to: target)
                            uploads.append(MediaUpload(file: target, fileName: ChatFileNames.sendable(item.name), mime: ChatFileNames.mime(for: target, name: item.name)))
                        }
                    } catch ImageNormalizer.Failure.tooLarge {
                        for upload in uploads { try? FileManager.default.removeItem(at: upload.file) }
                        return .failure(.typedRefusal("file_too_large"))
                    } catch {
                        for upload in uploads { try? FileManager.default.removeItem(at: upload.file) }
                        return .failure(.invalidInput)
                    }
                }
                return .success(uploads)
            }.value
            guard let self, self.epoch == current else {
                if case .success(let uploads) = staged { for upload in uploads { try? FileManager.default.removeItem(at: upload.file) } }
                return
            }
            self.mediaTasks["send"] = nil
            switch staged {
            case .success(let uploads): self.upload(MediaSendState(operationID: operationID, items: uploads))
            case .failure(let error): self.state.failure = error
            }
        }
    }

    private func upload(_ pending: MediaSendState) {
        guard mediaTasks["send"] == nil else { return }
        var sending = pending; sending.failure = nil
        state.mediaSend = sending
        let current = epoch
        let caption = ""
        mediaTasks["send"] = Task { [weak self, repository, account, conversation] in
            let groupID = await MainActor.run { self?.state.isGroup == true ? conversation : nil }
            let result = await repository.sendMedia(account: account, conversation: conversation, groupID: groupID, caption: caption, items: pending.items, operationID: pending.operationID)
            guard let self, self.epoch == current else { return }
            self.mediaTasks["send"] = nil
            switch result {
            case .success(let outcome) where outcome.state == .submitted:
                self.state.mediaSend = nil
                self.emit(.messageSubmitted(outcome.messageID))
                self.send(.refresh)
            case .success:
                self.state.mediaSend?.failure = .unavailableResource("chat.send.deliveryFailed")
            case .failure(let error):
                self.state.mediaSend?.failure = error
            }
        }
    }

    private func savePhoto(_ url: URL) {
        let current = epoch
        mediaTasks["save"] = Task { [weak self] in
            let saved = await PhotoLibrarySaver.save(url)
            guard let self, self.epoch == current else { return }
            self.mediaTasks["save"] = nil
            self.state.photoSaved = saved
        }
    }
}

/// File names and declared types for files sent as they are.
enum ChatFileNames {
    /// Control and directional characters removed, at most 255 bytes, never empty.
    static func sendable(_ name: String) -> String {
        var clean = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value) && $0 != "/" }))
        while clean.utf8.count > 255 { clean.removeFirst() }
        return clean.isEmpty ? "file" : clean
    }
    static func mime(for file: URL, name: String) -> String {
        switch MediaSniffer.format(of: file) {
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        case .gif: "image/gif"
        case .webp: "image/webp"
        case .heic: "image/heic"
        case .avif: "image/avif"
        case .mp4: "video/mp4"
        case .quicktime: "video/quicktime"
        case .unknown: name.lowercased().hasSuffix(".pdf") ? "application/pdf" : "application/octet-stream"
        }
    }
}

/// The current network class for the auto-download policy, from the system path monitor.
final class ChatNetwork: Sendable {
    static let shared = ChatNetwork()
    private let monitor = NWPathMonitor()
    private let value = Mutex(MediaPolicy.Network.constrained)
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let network: MediaPolicy.Network = path.status != .satisfied || path.isConstrained || ProcessInfo.processInfo.isLowPowerModeEnabled ? .constrained : (path.isExpensive ? .cellular : .wifi)
            self?.value.withLock { $0 = network }
        }
        monitor.start(queue: DispatchQueue(label: "org.ramflux.chat.network"))
    }
    var current: MediaPolicy.Network { value.withLock { $0 } }
}
