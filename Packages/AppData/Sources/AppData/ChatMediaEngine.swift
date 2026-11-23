// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CryptoKit
import RamfluxCore

/// The private media store: decrypted originals and the send outbox, per account, under
/// Application Support (not Caches: after the relay window the local copy is the only copy),
/// excluded from backup, with complete-unless-open file protection on iOS. Originals live in
/// `originals/<hash of conversation id>/<hash of message id>-<index>`; a sender's file name is
/// never used as a path.
///
/// Eviction policy: originals are never evicted silently. They leave the device only when the
/// sender erases the message, the user deletes it, or the user clears media in storage
/// management (per conversation or for the account); a cleared item whose relay window has
/// passed cannot be downloaded again. Staged outbox files leave when their send is admitted or
/// discarded, and unreferenced staged files older than ten minutes are swept after unlock.
/// Share copies are removed when the sheet closes. Decoded images live only in the bounded
/// memory cache of the image pipeline; there is no derived disk cache.
struct MediaStore: Sendable {
    let base: URL
    init(base: URL? = nil) {
        self.base = base ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("RamfluxMedia", isDirectory: true)
    }
    func accountRoot(_ account: String) -> URL { base.appendingPathComponent(Self.hash(account), isDirectory: true) }
    func originals(_ account: String) -> URL { accountRoot(account).appendingPathComponent("originals", isDirectory: true) }
    func outbox(_ account: String) -> URL { accountRoot(account).appendingPathComponent("outbox", isDirectory: true) }
    /// Transient copies for the share sheet, removed when the sheet closes.
    func share(_ account: String) -> URL { accountRoot(account).appendingPathComponent("share", isDirectory: true) }
    func conversation(_ account: String, _ conversation: String) -> URL { originals(account).appendingPathComponent(Self.hash(conversation), isDirectory: true) }
    func file(_ account: String, conversation: String, message: String, index: Int) -> URL {
        self.conversation(account, conversation).appendingPathComponent(Self.hash(MessagePage.normalizeIdentifier(message)) + "-" + String(index))
    }
    func file(_ account: String, _ attachment: AttachmentRecord) -> URL { file(account, conversation: attachment.conversationID, message: attachment.messageID, index: attachment.index) }
    func existing(_ account: String, _ attachment: AttachmentRecord) -> URL? {
        let url = file(account, attachment)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: Self.attributes)
        var root = base
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }
    /// Removes every stored original of a message (all indexes, in whichever conversation).
    func purge(_ account: String, message: String) {
        let prefix = Self.hash(MessagePage.normalizeIdentifier(message)) + "-"
        let root = originals(account)
        guard let groups = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for group in groups {
            let directory = root.appendingPathComponent(group, isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasPrefix(prefix) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
        }
    }
    func purgeConversation(_ account: String, conversation: String) { try? FileManager.default.removeItem(at: self.conversation(account, conversation)) }
    /// Downloaded originals and share copies only; staged files of queued sends stay.
    func purgeOriginals(_ account: String) {
        try? FileManager.default.removeItem(at: originals(account)); try? FileManager.default.removeItem(at: share(account))
    }
    func purgeAccount(_ account: String) { try? FileManager.default.removeItem(at: accountRoot(account)) }
    func usage(_ account: String) -> MediaUsage { MediaUsage(originals: Self.size(originals(account)), outbox: Self.size(outbox(account))) }
    func usage(_ account: String, conversation: String) -> Int64 { Self.size(self.conversation(account, conversation)) }
    /// Removes staged files no queued send refers to and older than `age` seconds.
    func sweepOutbox(_ account: String, keeping: Set<String>, age: TimeInterval = 600, now: Date = Date()) {
        let directory = outbox(account)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !keeping.contains(name) {
            let url = directory.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(modified) >= age { try? FileManager.default.removeItem(at: url) }
        }
    }
    static func size(_ directory: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in items { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }
    static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() }
    static var attributes: [FileAttributeKey: Any] {
        #if os(iOS)
        [.protectionKey: FileProtectionType.completeUnlessOpen, .posixPermissions: 0o700]
        #else
        [.posixPermissions: 0o700]
        #endif
    }
}

/// Runs attachment imports and uploads through the SDK. One instance per repository; imports
/// are de-duplicated per attachment and limited to three at a time per process.
actor ChatMediaEngine {
    static let chunk = 524_288
    private let gateway: ProxyGateway
    let store: MediaStore
    private let pause: @Sendable (Int) async throws -> Void
    private var enabled: Set<String> = []
    private var imports: [String: Task<MediaTransferState, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(gateway: ProxyGateway, store: MediaStore, pause: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .milliseconds($0)) }) {
        self.gateway = gateway; self.store = store; self.pause = pause
    }

    /// `attachment.enable {from_node: true}` once per account: the recipient needs the relay
    /// authority pin too. A repeated pin answers `duplicate_operation`, which counts as enabled.
    func enable(_ account: String) async throws {
        guard !enabled.contains(account) else { return }
        do { _ = try await gateway.call(.attachmentEnable, account: account, body: .object(["from_node": .bool(true)])) }
        catch { guard Self.code(error) == "duplicate_operation" else { throw error } }
        enabled.insert(account)
    }

    func state(_ account: String, _ attachment: AttachmentRecord) -> MediaTransferState? {
        if let url = store.existing(account, attachment) { return .ready(url) }
        return imports[key(account, attachment)] == nil ? nil : .downloading
    }

    func download(_ account: String, _ attachment: AttachmentRecord, now: Date = Date()) async -> MediaTransferState {
        if let url = store.existing(account, attachment) { return .ready(url) }
        if attachment.isExpired(now: now) { return .expired }
        let id = key(account, attachment)
        if let task = imports[id] { return await task.value }
        let task = Task { await self.runImport(account, attachment) }
        imports[id] = task
        let result = await task.value
        imports[id] = nil
        return result
    }

    func cancel(_ account: String, _ attachment: AttachmentRecord) { imports[key(account, attachment)]?.cancel() }
    /// Cancels every running import of the account (account purge).
    func cancelAll(_ account: String) { for (key, task) in imports where key.hasPrefix(account + "\u{0}") { task.cancel() } }

    private func runImport(_ account: String, _ attachment: AttachmentRecord) async -> MediaTransferState {
        await acquire(); defer { release() }
        var importID: String?
        do {
            try await enable(account)
            let begun = try await gateway.call(.attachmentImportBegin, account: account, body: .object([
                "message_id": .string(attachment.messageID), "index": .number(Double(attachment.index)),
                "operation_id": .string("import:" + MediaStore.hash(attachment.messageID) + ":" + String(attachment.index)),
            ]))
            let id = try ProxyGateway.text(begun, "import_id"); importID = id
            var generation = MessagePage.unsigned(begun["generation"]) ?? 1
            var length = MessagePage.unsigned(begun["plaintext_length"])
            var delay = 250
            while begun["state"] != .string("ready") {
                try Task.checkCancellation()
                let status = try await gateway.call(.attachmentImportStatus, account: account, body: .object(["import_id": .string(id)]))
                generation = MessagePage.unsigned(status["generation"]) ?? generation
                length = MessagePage.unsigned(status["plaintext_length"]) ?? length
                if status["state"] == .string("ready") { break }
                try await pause(delay); delay = min(delay * 2, 2_000)
            }
            guard let total = length else { throw AppFailure.invalidData }
            let directory = store.conversation(account, attachment.conversationID)
            try store.prepare(directory)
            let temporary = directory.appendingPathComponent(UUID().uuidString + ".part")
            guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: MediaStore.attributes) else { throw AppFailure.localStorage }
            defer { try? FileManager.default.removeItem(at: temporary) }
            let handle = try FileHandle(forWritingTo: temporary)
            var offset: UInt64 = 0
            do {
                while offset < total {
                    try Task.checkCancellation()
                    let read = try await gateway.call(.attachmentImportRead, account: account, body: .object([
                        "import_id": .string(id), "generation": .unsigned(generation), "offset": .unsigned(offset), "max_bytes": .number(Double(Self.chunk)),
                    ]))
                    guard let encoded = read["bytes"]?.string, let bytes = Self.base64URL(encoded), MessagePage.unsigned(read["offset"]) == offset else { throw AppFailure.invalidData }
                    guard !bytes.isEmpty || read["eof"] == .bool(true) else { throw AppFailure.invalidData }
                    try handle.write(contentsOf: bytes); offset += UInt64(bytes.count)
                    if read["eof"] == .bool(true) { break }
                }
                try handle.synchronize(); try handle.close()
            } catch { try? handle.close(); throw error }
            guard offset == total else { throw AppFailure.invalidData }
            let final = store.file(account, attachment)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: temporary, to: final)
            _ = try? await gateway.call(.attachmentImportFinish, account: account, body: .object(["import_id": .string(id)]))
            return .ready(final)
        } catch {
            if let importID { _ = try? await gateway.call(.attachmentImportCancel, account: account, body: .object(["import_id": .string(importID)])) }
            if error is CancellationError || Task.isCancelled { return .idle }
            let code = Self.code(error)
            if code == "attachment_deleted" { store.purge(account, message: attachment.messageID) }
            return MediaRefusal.state(code, failure: AppFailure.map(error))
        }
    }

    /// Streams each upload into `attachment.prepare.*` with the BLAKE3 digest, then sends one
    /// message with all prepares. Item keys are `<operation>:<index>`, as the CLI derives them,
    /// so a retry with the same operation resumes instead of uploading twice.
    func send(_ account: String, conversation: String, groupID: String?, caption: String, items: [MediaUpload], operationID: String) async -> RepositoryResult<SendOutcome> {
        guard (1...MessagePage.maxAttachments).contains(items.count) else { return .failure(.invalidInput) }
        do {
            try await enable(account)
            var prepares: [JSONValue] = []
            for (index, item) in items.enumerated() {
                prepares.append(.object(["prepare_id": .string(try await prepare(account, conversation: conversation, groupID: groupID, item: item, operationID: operationID + ":" + String(index)))]))
            }
            var body: [String: JSONValue] = ["conversation_id": .string(conversation), "text": .string(caption), "prepares": .array(prepares)]
            if let groupID { body["group_id"] = .string(groupID) }
            let result = try await gateway.call(.conversationSend, account: account, body: .object(body), operationID: operationID)
            let outcome = try NativeChatRepository.outcome(result, conversation: conversation)
            if outcome.state == .submitted { for item in items { try? FileManager.default.removeItem(at: item.file) } }
            return .success(outcome)
        } catch {
            let failure = MediaRefusal.sendFailure(Self.code(error), failure: AppFailure.map(error))
            EventDiagnostics.note("media send failed code=\(Self.code(error) ?? "none") mapped=\(failure) raw=\(EventDiagnostics.describe(error))")
            return .failure(failure)
        }
    }

    private func prepare(_ account: String, conversation: String, groupID: String?, item: MediaUpload, operationID: String) async throws -> String {
        var body: [String: JSONValue] = ["operation_id": .string(operationID), "file_name": .string(item.fileName), "mime": .string(item.mime)]
        if let groupID { body["kind"] = .string("group"); body["group_id"] = .string(groupID) } else { body["kind"] = .string("dm"); body["peer"] = .string(conversation) }
        let begun = try await gateway.call(.attachmentPrepareBegin, account: account, body: .object(body), operationID: operationID)
        let prepareID = try ProxyGateway.text(begun, "prepare_id")
        guard let generation = MessagePage.unsigned(begun["generation"]) else { throw AppFailure.invalidData }
        // A retry whose bytes the SDK already holds streams nothing again.
        guard begun["state"] == .string("accepting") else { return prepareID }
        // A resumed prepare (after a crash or relaunch) continues after the bytes the SDK has
        // accepted; those are only hashed again, because the digest covers the whole file.
        let accepted = MessagePage.unsigned(begun["accepted_through"]) ?? 0
        let handle = try FileHandle(forReadingFrom: item.file)
        defer { try? handle.close() }
        var digest = BLAKE3()
        var offset: UInt64 = 0
        while let data = try handle.read(upToCount: Self.chunk), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data)
            let end = offset + UInt64(data.count)
            if end > accepted {
                let skip = Int(accepted > offset ? accepted - offset : 0)
                let start = offset + UInt64(skip)
                _ = try await gateway.call(.attachmentPrepareChunk, account: account, body: .object([
                    "prepare_id": .string(prepareID), "generation": .unsigned(generation), "offset": .unsigned(start), "data_base64": .string(data.dropFirst(skip).base64EncodedString()),
                ]), operationID: operationID + ":c" + String(start))
            }
            offset = end
        }
        _ = try await gateway.call(.attachmentPrepareFinish, account: account, body: .object([
            "prepare_id": .string(prepareID), "generation": .unsigned(generation), "plaintext_length": .unsigned(offset), "plaintext_digest": .string(digest.hex()),
        ]), operationID: operationID + ":f")
        return prepareID
    }

    /// Retires the message's grants on the relay. Until `message.delete` with scope everyone
    /// does this itself (request R7), the client calls it after erasing for everyone.
    func revoke(_ account: String, message: String) async -> RepositoryResult<Void> {
        store.purge(account, message: message)
        do {
            let result = try await gateway.call(.attachmentRevoke, account: account, body: .object(["message_id": .string(message)]))
            _ = result
            return .success(())
        } catch {
            return Self.code(error) == "retirement_pending" ? .success(()) : .failure(AppFailure.map(error))
        }
    }

    private func acquire() async {
        if running < 3 { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
    private func key(_ account: String, _ attachment: AttachmentRecord) -> String { account + "\u{0}" + attachment.id }

    /// The attachment refusal code of a failure, from the typed name, reason or response body.
    static func code(_ error: any Error) -> String? {
        guard let failure = error as? CoreFailure else { return nil }
        var candidates = [failure.typedName, failure.reasonCode, failure.response?["error"]?["code"]?.string, failure.response?["error"]?["name"]?.string,
                          failure.response?["error"]?["details"]?["code"]?.string, failure.response?["body"]?["code"]?.string]
        if let sealed = failure.sealedResponse, let frame = try? sealed.consume({ try JSONDecoder().decode(JSONValue.self, from: Data($0)) }) {
            let response = frame["response"] ?? frame
            candidates += [response["error"]?["code"]?.string, response["error"]?["name"]?.string, response["error"]?["details"]?["code"]?.string, response["body"]?["code"]?.string]
        }
        for candidate in candidates.compactMap({ $0 }) {
            if MediaRefusal.known.contains(candidate) { return candidate }
            if let prefix = candidate.split(separator: ":").first.map(String.init), MediaRefusal.known.contains(prefix) { return prefix }
        }
        return nil
    }

    static func base64URL(_ text: String) -> Data? {
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard += "=" }
        return Data(base64Encoded: standard)
    }
}
