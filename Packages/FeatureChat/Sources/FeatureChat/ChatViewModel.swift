// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class ChatViewModel {
    public internal(set) var state: ChatState
    public let conversation: String
    let account: String
    let repository: any ChatRepository
    let emit: (ChatEvent) -> Void
    let now: @Sendable () -> Date
    /// Media steps: per-attachment imports, the trust lookup and the send pipeline.
    @ObservationIgnored var mediaTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var trust: MediaPolicy.Sender?
    @ObservationIgnored var pendingSave: URL?
    @ObservationIgnored let network: @Sendable () -> MediaPolicy.Network
    @ObservationIgnored private var window: TimelineWindow
    @ObservationIgnored private var load: Task<Void, Never>?
    @ObservationIgnored private var older: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var outboxTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored var galleryTask: Task<Void, Never>?
    @ObservationIgnored var galleryCursor: MessageCursor?
    @ObservationIgnored private var sideTasks: [Task<Void, Never>] = []
    @ObservationIgnored var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    /// A page read or change follow is in flight; invalidations arriving meanwhile are coalesced.
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var lastMarked: MessageOrder?
    @ObservationIgnored private var marking = false
    @ObservationIgnored private var typingSentAt: Date?
    public init(repository: any ChatRepository, account: String, conversation: String, isGroup: Bool = false, title: String? = nil, state: ChatState = ChatState(), windowCapacity: Int = 600, now: @escaping @Sendable () -> Date = Date.init, network: (@Sendable () -> MediaPolicy.Network)? = nil, emit: @escaping (ChatEvent) -> Void) {
        self.repository = repository; self.account = account; self.conversation = conversation; self.now = now; self.network = network ?? { ChatNetwork.shared.current }
        var initial = state; initial.conversationID = conversation; initial.isGroup = isGroup; initial.displayTitle = title ?? conversation
        self.state = initial; self.emit = emit; window = TimelineWindow(capacity: windowCapacity)
    }
    public func send(_ action: ChatAction) {
        switch action {
        case .callRequested: if state.isGroup { state.failure = repository.unavailable(.calls) } else { emit(.navigate(.calls(conversation))) }
        case .appeared: restoreDraft(); reload(); observe()
        case .refresh: reload(); observe()
        case .loadOlder: loadOlder()
        case .jumpToLatest: reload()
        case .displayed(let id): markRead(id)
        case .draftChanged(let text):
            guard text.utf8.count <= 65_536 else { return }
            state.draft = text; saveDraft(text); typing(active: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .send: submitComposer()
        case .retrySameSend: retryHeld()
        case .retryOutbox(let id): runOutbox { repository, account, conversation in await repository.retryOutbox(account: account, conversation: conversation, operationID: id) }
        case .discardOutbox(let id):
            outboxTask = Task { [weak self, repository, account, conversation] in
                _ = await repository.discardOutbox(account: account, conversation: conversation, operationID: id)
                let entries = await repository.outbox(account: account, conversation: conversation)
                guard let self, !Task.isCancelled else { return }
                self.state.outbox = entries
            }
        case .openActions(let id): if visible(id) { state.actionTarget = id }
        case .closeActions: state.actionTarget = nil
        case .beginReply(let id): state.actionTarget = nil; beginReply(id)
        case .beginEdit(let id): state.actionTarget = nil; beginEdit(id)
        case .cancelComposer: cancelComposer()
        case .beginReact(let id):
            state.actionTarget = nil
            guard visible(id) else { return }
            state.reactionTarget = id; state.reactionRemove = false
        case .reactionMode(let remove): state.reactionRemove = remove
        case .chooseReaction(let token):
            if state.reactionTarget == nil, let target = state.actionTarget { state.reactionTarget = target; state.actionTarget = nil }
            react(token, remove: false)
        case .removeReaction(let token): react(token, remove: true)
        case .cancelReaction: state.reactionTarget = nil; state.reactionRemove = false
        case .requestDelete(let id, let scope):
            state.actionTarget = nil
            guard let message = state.messages.first(where: { $0.id == id }), visible(id), scope == .local || message.isOwn == true else { return }
            state.pendingDelete = PendingMessageDelete(messageID: id, scope: scope)
        case .cancelDelete: state.pendingDelete = nil
        case .confirmDelete: confirmDelete()
        case .mediaTapped, .revealMedia, .cancelMedia, .closePreview, .saveToPhotos, .attachRequested, .closeAttach, .cameraRequested, .attachPicked, .permissionResolved, .photoSaved, .shareMedia, .shareFinished, .forwardRequested, .forwardTo, .removeDraftItem, .draftCaptionChanged, .sendMediaDraft, .cancelMediaDraft, .openAlbum, .closeAlbum:
            handleMedia(action)
        case .openGallery, .closeGallery, .galleryTab, .galleryMore: handleGallery(action)
        case .clearMediaRequested: state.details?.confirmClear = true
        case .clearMediaCancelled: state.details?.confirmClear = false
        case .clearMediaConfirmed: clearConversationMedia()
        case .detailsRequested: openDetails()
        case .closeDetails: detailsTask?.cancel(); state.details = nil
        case .setMuted(let muted): setMuted(muted)
        case .openSafetyNumber:
            guard let principal = state.details?.details?.peerPrincipal else { return }
            state.details = nil; emit(.navigate(.safetyNumber(principal)))
        case .disappeared, .conceal:
            if !state.draft.isEmpty || action == .conceal { saveDraft(state.draft) }
            if typingSentAt != nil { typing(active: false) }
            epoch &+= 1; readID &+= 1; watchID &+= 1
            load?.cancel(); older?.cancel(); mutation?.cancel(); observer?.cancel(); outboxTask?.cancel(); detailsTask?.cancel()
            observer = nil; pendingRefresh = false; marking = false; reading = false; older = nil; window = TimelineWindow(capacity: window.capacity)
            state.sending = false; state.loading = false; state.loadingOlder = false; state.messages = []; state.outbox = []; state.pendingDelete = nil
            state.composer = nil; state.reactionTarget = nil; state.reactionRemove = false; state.held = nil; state.actionTarget = nil; state.details = nil
            state.olderAvailable = false; state.detached = false
            // Concealed UI keeps no message text; the draft stays in the repository's memory store.
            stopMedia(conceal: action == .conceal)
            if action == .conceal { state.draft = "" }
        }
    }
    private func visible(_ id: String) -> Bool {
        state.messages.contains { $0.id == id && $0.kind != .deleted && $0.kind != .callHistory }
    }
    private func busy() -> Bool { state.sending || state.held != nil }
    private func beginReply(_ id: String) {
        guard !busy(), let message = state.messages.first(where: { $0.id == id }), visible(id) else { return }
        let preview = switch message.kind { case .text(let text): text; default: "" }
        state.composer = .reply(messageID: id, preview: preview); state.reactionTarget = nil
    }
    private func beginEdit(_ id: String) {
        guard !busy(), let message = state.messages.first(where: { $0.id == id }), message.isOwn == true, case .text(let text) = message.kind else { return }
        state.composer = .edit(messageID: id, previousDraft: state.draft); state.draft = text; state.reactionTarget = nil
    }
    private func cancelComposer() {
        guard state.held == nil else { return }
        if case .edit(_, let previous) = state.composer { state.draft = previous }
        state.composer = nil
    }
    private func submitComposer() {
        guard !state.sending, state.held == nil else { return }
        guard !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch state.composer {
        case .edit(let messageID, _):
            let attempt = FrozenSend(operationID: UUID().uuidString, text: state.draft)
            state.held = .revision(operationID: attempt.operationID, messageID: messageID, text: attempt.text, reply: false)
            runHeld { [repository, account, conversation] in await repository.edit(account: account, conversation: conversation, message: messageID, text: attempt.text, operationID: attempt.operationID) }
        case .reply(let messageID, _):
            let attempt = FrozenSend(operationID: UUID().uuidString, text: state.draft)
            state.held = .revision(operationID: attempt.operationID, messageID: messageID, text: attempt.text, reply: true)
            runHeld { [repository, account, conversation] in await repository.reply(account: account, conversation: conversation, message: messageID, text: attempt.text, operationID: attempt.operationID) }
        case nil:
            let attempt = FrozenSend(operationID: UUID().uuidString, text: state.draft)
            // The text moves from the composer into a local outbox row at once (MOB-B08); it is
            // never drawn as a delivered message until the read model has it.
            state.outbox.append(OutboxEntry(operationID: attempt.operationID, text: attempt.text, created: Int64(now().timeIntervalSince1970), state: .sending))
            state.draft = ""; saveDraft(""); typing(active: false)
            let current = epoch
            outboxTask = Task { [weak self, repository, account, conversation] in
                let result = await repository.enqueue(account: account, conversation: conversation, text: attempt.text, operationID: attempt.operationID)
                guard !Task.isCancelled, let self, self.epoch == current else { return }
                switch result {
                case .success(let admitted): await self.mirrorOutbox(admitted)
                case .failure(let error):
                    // Not queued at all (invalid or no SDK): the text goes back to the composer.
                    self.state.outbox.removeAll { $0.operationID == attempt.operationID }
                    if self.state.draft.isEmpty { self.state.draft = attempt.text; self.saveDraft(attempt.text) }
                    self.state.failure = error
                }
            }
        }
    }
    /// Runs an outbox step, then mirrors the repository's queue and follows newly admitted rows.
    private func runOutbox(_ work: @escaping @Sendable (any ChatRepository, String, String) async -> [SendOutcome]) {
        let current = epoch
        outboxTask = Task { [weak self, repository, account, conversation] in
            let admitted = await work(repository, account, conversation)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            await self.mirrorOutbox(admitted)
        }
    }
    func mirrorOutbox(_ admitted: [SendOutcome]) async {
        let current = epoch
        let entries = await repository.outbox(account: account, conversation: conversation)
        guard epoch == current else { return }
        state.outbox = entries
        state.offline = entries.contains { $0.state == .queued }
        for outcome in admitted { emit(.messageSubmitted(outcome.messageID)) }
        if !admitted.isEmpty { refresh() }
    }
    private func retryHeld() {
        guard !state.sending, let held = state.held else { return }
        switch held {
        case .revision(let operationID, let messageID, let text, let reply):
            runHeld { [repository, account, conversation] in
                reply ? await repository.reply(account: account, conversation: conversation, message: messageID, text: text, operationID: operationID)
                    : await repository.edit(account: account, conversation: conversation, message: messageID, text: text, operationID: operationID)
            }
        case .reaction(let operationID, let messageID, let token, let remove):
            runHeld { [repository, account, conversation] in await repository.react(account: account, conversation: conversation, message: messageID, token: token, remove: remove, operationID: operationID) }
        case .deletion(let operationID, let messageID, let scope):
            runDeletion(operationID: operationID, messageID: messageID, scope: scope)
        }
    }
    private func react(_ token: String, remove: Bool) {
        guard !busy(), let messageID = state.reactionTarget, ChatReactionPalette.accepts(token) else { return }
        let operationID = UUID().uuidString
        state.reactionTarget = nil; state.reactionRemove = false
        state.held = .reaction(operationID: operationID, messageID: messageID, token: token, remove: remove)
        runHeld { [repository, account, conversation] in await repository.react(account: account, conversation: conversation, message: messageID, token: token, remove: remove, operationID: operationID) }
    }
    private func confirmDelete() {
        guard !busy(), let pending = state.pendingDelete else { return }
        let operationID = UUID().uuidString
        state.pendingDelete = nil
        state.held = .deletion(operationID: operationID, messageID: pending.messageID, scope: pending.scope)
        // Erase for everyone also retires the attachment grants on the relay until the SDK does
        // it itself (request R7); a failed revoke leaves the grants to expire after 24 hours.
        runDeletion(operationID: operationID, messageID: pending.messageID, scope: pending.scope)
    }
    /// Erase for everyone of a message with media also revokes its grants, on the first attempt
    /// and on every retry; a revoke that fails is kept by the repository and retried later.
    private func runDeletion(operationID: String, messageID: String, scope: MessageDeleteScope) {
        let revoke = scope == .everyone && state.messages.contains { $0.id == messageID && !$0.attachments.isEmpty }
        runHeld { [repository, account, conversation] in
            let result = await repository.delete(account: account, conversation: conversation, message: messageID, scope: scope, operationID: operationID)
            if case .success = result, revoke { _ = await repository.revokeMedia(account: account, message: messageID) }
            return result
        }
    }
    private func runHeld(_ work: @escaping @Sendable () async -> RepositoryResult<Void>) {
        state.sending = true; state.failure = nil; let current = epoch; let held = state.held
        mutation = Task { [weak self] in
            let result = await work()
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.sending = false
            switch result {
            case .success:
                self.finish(held); self.refresh()
            case .failure(let error):
                self.state.failure = error
                if let pending = await self.repository.mutationState(account: self.account, conversation: self.conversation), pending.unresolved, let restored = Self.held(pending) {
                    self.state.held = restored
                } else if error != .outcomeUnknown && error != .offline {
                    self.state.held = nil
                }
            }
        }
    }
    private func finish(_ held: HeldMutation?) {
        switch held {
        case .revision(_, _, let text, let reply):
            if reply {
                if state.draft == text { state.draft = ""; saveDraft("") }
                state.composer = nil
            } else if case .edit(_, let previous) = state.composer {
                state.draft = previous; state.composer = nil
            }
        default: break
        }
        state.held = nil
    }

    // MARK: Window

    /// Reads the newest page and restarts change following from its snapshot.
    private func reload() {
        readID &+= 1; let current = readID; state.loading = true; reading = true; load?.cancel(); older?.cancel(); older = nil; state.loadingOlder = false
        let capacity = window.capacity
        load = Task { [weak self, repository, account, conversation] in
            let result = await repository.messages(account: account, conversation: conversation, before: nil)
            let mutation = await repository.mutationState(account: account, conversation: conversation)
            let admitted = await repository.flushOutbox(account: account, conversation: conversation)
            let entries = await repository.outbox(account: account, conversation: conversation)
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false; self.reading = false
            if let mutation, mutation.unresolved, let restored = Self.held(mutation) {
                self.state.held = restored
                self.state.failure = .outcomeUnknown
            }
            self.state.outbox = entries
            self.state.offline = entries.contains { $0.state == .queued }
            for outcome in admitted { self.emit(.messageSubmitted(outcome.messageID)) }
            switch result {
            case .success(let page):
                var next = TimelineWindow(capacity: capacity); next.reset(page)
                self.publish(next)
                if !admitted.isEmpty || self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
            case .failure(let error):
                self.state.failure = error
                if error == .locked { self.window = TimelineWindow(capacity: capacity); self.state.messages = [] }
            }
        }
    }
    /// Follows changes after the window's journal cursor; falls back to a reload when the cursor
    /// is unknown, pruned or the window asks to be rebuilt.
    private func refresh() {
        guard window.loaded, let journal = window.journal, !window.needsReload else { reload(); return }
        if reading { pendingRefresh = true; return }
        readID &+= 1; let current = readID; reading = true; load?.cancel()
        let snapshot = window
        load = Task { [weak self, repository, account, conversation] in
            var working = snapshot
            var cursor = journal
            var failure: AppFailure?
            for _ in 0..<64 {
                switch await repository.changes(account: account, conversation: conversation, after: cursor) {
                case .success(let batch):
                    let input = working
                    working = await Task.detached { var next = input; next.apply(batch); return next }.value
                    cursor = batch.nextAfter
                    if !batch.more { failure = nil; break }
                    continue
                case .failure(let error): failure = error
                }
                break
            }
            let admitted = await repository.flushOutbox(account: account, conversation: conversation)
            let entries = await repository.outbox(account: account, conversation: conversation)
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.reading = false
            self.state.outbox = entries
            self.state.offline = entries.contains { $0.state == .queued }
            for outcome in admitted { self.emit(.messageSubmitted(outcome.messageID)) }
            switch failure {
            case .resyncRequired?, .typedRefusal("resync_required")?, .invalidData?: self.reload(); return
            case .some(let error): self.state.failure = error
            case nil: self.publish(working)
            }
            if working.needsReload { self.reload(); return }
            if self.pendingRefresh || !admitted.isEmpty { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func loadOlder() {
        guard window.loaded, let cursor = window.nextBefore, older == nil, !reading else { return }
        state.loadingOlder = true; let current = readID
        let snapshot = window
        older = Task { [weak self, repository, account, conversation] in
            let result = await repository.messages(account: account, conversation: conversation, before: cursor)
            let merged: TimelineWindow? = switch result {
            case .success(let page): await Task.detached { var next = snapshot; next.appendOlder(page); return next }.value
            case .failure: nil
            }
            guard let self, !Task.isCancelled, self.readID == current else { return }
            self.older = nil
            self.state.loadingOlder = false
            if let merged { self.publish(merged) } else if case .failure(let error) = result { self.state.failure = error }
        }
    }
    private func publish(_ next: TimelineWindow) {
        window = next
        state.messages = next.records; state.olderAvailable = next.hasOlder; state.detached = next.detached
        syncMedia()
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let current = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await event in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch event { case .invalidated: self.refresh(); case .failed(let error): self.state.failure = error }
            }
            await observation.stop()
            if let self, self.watchID == current { self.observer = nil }
        }
    }

    // MARK: Read position, typing, drafts

    /// Marks the conversation read through the newest incoming message the timeline displayed.
    private func markRead(_ id: String) {
        guard let message = state.messages.first(where: { $0.id == id }), message.isOwn != true, message.kind != .deleted, let order = message.order else { return }
        guard lastMarked.map({ order > $0 }) ?? true, !marking else { return }
        marking = true; lastMarked = order
        let current = epoch
        sideTasks.append(Task { [weak self, repository, account, conversation] in
            let result = await repository.markRead(account: account, conversation: conversation, message: id)
            guard let self, self.epoch == current else { return }
            self.marking = false
            if case .failure = result, self.lastMarked == order { self.lastMarked = nil }
        })
    }
    /// Typing is best effort: at most one start per four seconds while the draft has text, and
    /// one stop when it empties, is sent, or the chat goes away. Failures are ignored.
    private func typing(active: Bool) {
        let time = now()
        if active {
            if let sent = typingSentAt, time.timeIntervalSince(sent) < 4 { return }
            typingSentAt = time
        } else {
            guard typingSentAt != nil else { return }
            typingSentAt = nil
        }
        sideTasks.removeAll { $0.isCancelled }
        sideTasks.append(Task { [repository, account, conversation] in _ = await repository.setTyping(account: account, conversation: conversation, active: active) })
    }
    private func restoreDraft() {
        guard state.draft.isEmpty, state.composer == nil else { return }
        let current = epoch
        sideTasks.append(Task { [weak self, repository, account, conversation] in
            let draft = await repository.draft(account: account, conversation: conversation)
            guard let self, self.epoch == current, self.state.draft.isEmpty, !draft.isEmpty else { return }
            self.state.draft = draft
        })
    }
    private func saveDraft(_ text: String) {
        sideTasks.append(Task { [repository, account, conversation] in await repository.saveDraft(account: account, conversation: conversation, text: text) })
    }

    // MARK: Details

    private func openDetails() {
        state.details = ChatDetailsState()
        let anchor = state.isGroup ? nil : state.messages.first(where: { $0.isOwn == false && $0.authorAnchor != nil })?.authorAnchor
        detailsTask?.cancel()
        detailsTask = Task { [weak self, repository, account, conversation] in
            let result = await repository.details(account: account, conversation: conversation, peerAnchor: anchor)
            let storage = await repository.mediaUsage(account: account, conversation: conversation)
            guard !Task.isCancelled, let self, self.state.details != nil else { return }
            switch result {
            case .success(let details): self.state.details = ChatDetailsState(loading: false, details: details)
            case .failure(let error): self.state.details = ChatDetailsState(loading: false, failure: error)
            }
            self.state.details?.storage = storage
        }
    }
    /// Clears this conversation's downloaded media after the user confirmed; items whose relay
    /// window passed cannot be downloaded again.
    private func clearConversationMedia() {
        guard state.details?.confirmClear == true else { return }
        state.details?.confirmClear = false
        for task in mediaTasks.values { task.cancel() }
        mediaTasks = [:]
        detailsTask = Task { [weak self, repository, account, conversation] in
            await repository.purgeConversationMedia(account: account, conversation: conversation)
            let storage = await repository.mediaUsage(account: account, conversation: conversation)
            guard !Task.isCancelled, let self else { return }
            self.state.details?.storage = storage
            self.state.media = [:]; self.state.preview = nil
            self.syncMedia()
        }
    }
    private func setMuted(_ muted: Bool) {
        guard var details = state.details, !details.muting, details.details != nil else { return }
        details.muting = true; details.failure = nil; state.details = details
        let operationID = UUID().uuidString
        detailsTask = Task { [weak self, repository, account, conversation] in
            let result = await repository.setMuted(account: account, conversation: conversation, muted: muted, operationID: operationID)
            guard !Task.isCancelled, let self, var current = self.state.details, let known = current.details else { return }
            current.muting = false
            switch result {
            case .success(let value): current.details = ChatDetails(muted: value, muteUntil: nil, peerPrincipal: known.peerPrincipal, peerName: known.peerName)
            case .failure(let error): current.failure = error
            }
            self.state.details = current
        }
    }

    public func settle() async {
        await mutation?.value; await outboxTask?.value; await detailsTask?.value
        while true { let current = readID; await load?.value; await older?.value; if current == readID { break } }
        for task in sideTasks { await task.value }
    }
    private static func held(_ pending: PendingChatMutation) -> HeldMutation? {
        switch pending.key.kind {
        case .edit: return .revision(operationID: pending.operationID, messageID: pending.key.message, text: pending.key.text, reply: false)
        case .reply: return .revision(operationID: pending.operationID, messageID: pending.key.message, text: pending.key.text, reply: true)
        case .react: return .reaction(operationID: pending.operationID, messageID: pending.key.message, token: pending.key.token, remove: pending.key.remove)
        case .deletion:
            guard let scope = MessageDeleteScope(rawValue: pending.key.scope) else { return nil }
            return .deletion(operationID: pending.operationID, messageID: pending.key.message, scope: scope)
        }
    }
    deinit { load?.cancel(); older?.cancel(); mutation?.cancel(); observer?.cancel(); outboxTask?.cancel(); detailsTask?.cancel() }
}
