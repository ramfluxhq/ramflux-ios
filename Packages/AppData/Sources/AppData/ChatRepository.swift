// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum ChatCapability: Sendable { case attachmentTransfer, calls, details }
public enum MessageDeleteScope: String, Sendable, Equatable { case local, everyone }
public struct SendOutcome: Equatable, Sendable {
    public enum State: String, Sendable { case submitted, failed }
    public let messageID: String
    public let state: State
    public init(messageID: String, state: State) { self.messageID = messageID; self.state = state }
}
public struct ChatMutationKey: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case edit, reply, react, deletion }
    public let kind: Kind
    public let message: String
    public let text: String
    public let token: String
    public let remove: Bool
    public let scope: String
    public init(kind: Kind, message: String, text: String = "", token: String = "", remove: Bool = false, scope: String = "") {
        self.kind = kind; self.message = message; self.text = text; self.token = token; self.remove = remove; self.scope = scope
    }
}
public struct PendingChatMutation: Equatable, Sendable {
    public let operationID: String
    public let key: ChatMutationKey
    public let unresolved: Bool
    public init(operationID: String, key: ChatMutationKey, unresolved: Bool) {
        self.operationID = operationID; self.key = key; self.unresolved = unresolved
    }
}
public protocol ChatRepository: Sendable {
    func unavailable(_ capability: ChatCapability) -> AppFailure
    func sendState(account: String, conversation: String) async -> PendingChatSend?
    func mutationState(account: String, conversation: String) async -> PendingChatMutation?
    /// One read-model page, newest first. `before` is the previous page's `nextBefore`.
    func messages(account: String, conversation: String, before: MessageCursor?) async -> RepositoryResult<MessageWindowPage>
    /// Rows changed after the journal cursor, oldest change first.
    func changes(account: String, conversation: String, after: UInt64) async -> RepositoryResult<MessageChangeBatch>
    func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome>
    /// Unadmitted sends of the conversation in the order the user sent them.
    func outbox(account: String, conversation: String) async -> [OutboxEntry]
    /// Queues a send and flushes the queue. Returns the outcomes the SDK admitted in this flush.
    func enqueue(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<[SendOutcome]>
    /// Sends queued entries with their original keys; called when the chat appears or the
    /// account changes (for example after the connection returns).
    func flushOutbox(account: String, conversation: String) async -> [SendOutcome]
    /// Puts a failed entry back into the queue with its original key and text, then flushes.
    func retryOutbox(account: String, conversation: String, operationID: String) async -> [SendOutcome]
    func discardOutbox(account: String, conversation: String, operationID: String) async -> Bool
    func edit(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void>
    func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void>
    func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) async -> RepositoryResult<Void>
    func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) async -> RepositoryResult<Void>
    /// Marks the conversation read through `message` for this device (`message.receipt.read`).
    func markRead(account: String, conversation: String, message: String) async -> RepositoryResult<Void>
    /// Best-effort typing indicator over the live session; never queued or retried.
    func setTyping(account: String, conversation: String, active: Bool) async -> RepositoryResult<Void>
    func details(account: String, conversation: String, peerAnchor: String?) async -> RepositoryResult<ChatDetails>
    func setMuted(account: String, conversation: String, muted: Bool, operationID: String) async -> RepositoryResult<Bool>
    func draft(account: String, conversation: String) async -> String
    func saveDraft(account: String, conversation: String, text: String) async
    /// The stored original when it is on this device, `.downloading` while an import runs, else nil.
    func mediaState(account: String, attachment: AttachmentRecord) async -> MediaTransferState?
    /// Imports, decrypts and stores one attachment; returns its final state.
    func download(account: String, attachment: AttachmentRecord) async -> MediaTransferState
    func cancelDownload(account: String, attachment: AttachmentRecord) async
    /// The protected directory where normalised files wait for upload.
    func mediaOutbox(account: String) async -> URL?
    /// Queues a media send (staged outbox files, optional caption) like a text send and flushes
    /// the queue. The files are erased when the SDK admits the send or the entry is discarded.
    func enqueueMedia(account: String, conversation: String, groupID: String?, caption: String, items: [MediaUpload], operationID: String) async -> RepositoryResult<[SendOutcome]>
    /// Retires a message's attachment grants on the relay and drops local copies. The revoke is
    /// remembered until it succeeds and retried on the next flush or after unlock.
    func revokeMedia(account: String, message: String) async -> RepositoryResult<Void>
    /// Clears downloaded originals of the account (staged files of queued sends stay).
    func purgeAccountMedia(account: String) async
    func mediaUsage(account: String, conversation: String) async -> Int64
    /// Clears downloaded originals of one conversation.
    func purgeConversationMedia(account: String, conversation: String) async
    /// Restores the account's sealed unsent state after unlock and resumes queued sends in every
    /// conversation with their original operation ids, plus pending revokes.
    func resumeAfterUnlock(account: String) async -> [SendOutcome]
    /// Writes unsent state to the sealed vault and drops it from memory (app lock).
    func sealForLock(account: String) async
    /// Erases all chat state of the account on this device: queued sends, drafts, pending
    /// revokes, the sealed vault and its keychain key, staged files and stored media.
    func purgeAccount(account: String) async
    /// A temporary copy of a stored original under a sanitised original name, for the share
    /// sheet; removed with `removeShareCopy` when the sheet closes.
    func shareCopy(account: String, file: URL, name: String) async -> URL?
    func removeShareCopy(account: String) async
    /// Forwards a message to another conversation: text is queued as text; attachments are
    /// imported when not on this device, copied into the outbox and queued as a new media send,
    /// so the SDK uploads them again with new keys for the new recipients.
    func forward(account: String, text: String, attachments: [AttachmentRecord], to conversation: String, groupID: String?, operationID: String) async -> RepositoryResult<[SendOutcome]>
    func mediaUsage(account: String) async -> MediaUsage
    func observe(account: String) async -> RepositoryObservation
    /// Typing updates of peers in the conversation from `message.transient`; finishes at once
    /// when no transient source is connected.
    func typing(account: String, conversation: String) async -> AsyncStream<TypingEvent>
}
public struct NativeChatRepository: ChatRepository {
    private let sends = RetainedMutation<String, SendOutcome>()
    private let mutations = RetainedMutation<ChatMutationKey, Void>()
    private let queue: ChatOutbox
    private let background: any MediaBackgroundAssertion
    private let transients: (any ChatTransientSource)?
    private let devices = OwnDeviceCache()
    private let media: ChatMediaEngine
    public func sendState(account: String, conversation: String) async -> PendingChatSend? {
        guard let entry = await sends.snapshot(scope: Self.scope(account, conversation)) else { return nil }
        return PendingChatSend(operationID: entry.operationID, text: entry.arguments, unresolved: entry.unresolved, result: entry.result)
    }
    public func mutationState(account: String, conversation: String) async -> PendingChatMutation? {
        guard let entry = await mutations.snapshot(scope: Self.mutationScope(account, conversation)) else { return nil }
        return PendingChatMutation(operationID: entry.operationID, key: entry.arguments, unresolved: entry.unresolved)
    }
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, updates: NativeUpdateSource, transients: (any ChatTransientSource)? = nil) { self.init(client: client, updates: updates, mediaRoot: nil, vaultKeys: KeychainChatVaultKeys(), transients: transients) }
    /// Without `vaultKeys` unsent state stays in process memory (tests).
    init(client: RamfluxClient, updates: NativeUpdateSource, mediaRoot: URL?, vaultRoot: URL? = nil, vaultKeys: (any ChatVaultKeys)? = nil, background: any MediaBackgroundAssertion = MediaBackgroundTransfer.system, transients: (any ChatTransientSource)? = nil,
         pause: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .milliseconds($0)) }) {
        let gateway = ProxyGateway(proxy: SDKProxy(client: client))
        self.gateway = gateway; self.updates = updates; self.background = background; self.transients = transients
        let store = MediaStore(base: mediaRoot)
        media = ChatMediaEngine(gateway: gateway, store: store, pause: pause)
        queue = ChatOutbox(vault: vaultKeys.map { ChatVault(base: vaultRoot, keys: $0, outbox: { store.outbox($0) }) })
    }
    public func unavailable(_ capability: ChatCapability) -> AppFailure { ChatUnavailable.failure(capability) }
    public func messages(account: String, conversation: String, before: MessageCursor?) async -> RepositoryResult<MessageWindowPage> {
        guard Self.identity(conversation) else { return .failure(.invalidInput) }
        do {
            var body: [String: JSONValue] = ["conversation_id": .string(conversation), "read_model": .bool(true), "limit": .number(Double(Self.pageSize))]
            if let before { body["before_order_key"] = before.value }
            let page = try MessagePage.page(body: try await gateway.call(.messageRead, account: account, body: .object(body)), conversation: conversation)
            purgeErased(account, page.records)
            return .success(page)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func changes(account: String, conversation: String, after: UInt64) async -> RepositoryResult<MessageChangeBatch> {
        guard Self.identity(conversation) else { return .failure(.invalidInput) }
        do {
            let body: JSONValue = .object(["conversation_id": .string(conversation), "after_sequence": .unsigned(after), "limit": .number(Double(Self.pageSize))])
            let batch = try MessagePage.changes(body: try await gateway.call(.messageRead, account: account, body: body), conversation: conversation)
            purgeErased(account, batch.changes.compactMap { if case .row(let record) = $0 { record } else { nil } })
            return .success(batch)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        guard Self.usableText(text), Self.identity(conversation), Self.identity(operationID) else { return .failure(.invalidInput) }
        return await sends.run(scope: Self.scope(account, conversation), arguments: text, operationID: operationID) { [gateway] in
        do {
            let body = try await gateway.call(.conversationSend, account: account, body: .object(["conversation_id": .string(conversation), "text": .string(text)]), operationID: operationID)
            return .success(try Self.outcome(body, conversation: conversation))
        } catch { return .failure(AppFailure.map(error)) }
        }
    }
    public func outbox(account: String, conversation: String) async -> [OutboxEntry] { await queue.entries(account, conversation) }
    public func enqueue(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<[SendOutcome]> {
        guard Self.usableText(text), Self.identity(conversation), Self.identity(operationID) else { return .failure(.invalidInput) }
        await queue.enqueue(account, conversation, entry: OutboxEntry(operationID: operationID, text: text, created: Int64(Date().timeIntervalSince1970), state: .queued))
        return .success(await flushOutbox(account: account, conversation: conversation))
    }
    public func enqueueMedia(account: String, conversation: String, groupID: String?, caption: String, items: [MediaUpload], operationID: String) async -> RepositoryResult<[SendOutcome]> {
        guard Self.identity(conversation), Self.identity(operationID), caption.utf8.count <= 65_536, groupID.map(Self.identity) ?? true,
              (1...MessagePage.maxAttachments).contains(items.count) else { return .failure(.invalidInput) }
        let outbox = media.store.outbox(account).standardizedFileURL.path
        guard items.allSatisfy({ $0.file.standardizedFileURL.deletingLastPathComponent().path == outbox && FileManager.default.fileExists(atPath: $0.file.path)
            && (1...256).contains($0.fileName.utf8.count) && (1...256).contains($0.mime.utf8.count) }) else { return .failure(.invalidInput) }
        await queue.enqueue(account, conversation, entry: OutboxEntry(operationID: operationID, text: caption, created: Int64(Date().timeIntervalSince1970), state: .queued, groupID: groupID, media: items))
        return .success(await flushOutbox(account: account, conversation: conversation))
    }
    public func flushOutbox(account: String, conversation: String) async -> [SendOutcome] {
        await retryRevokes(account)
        return await queue.flush(account, conversation) { [media, background] entry in
            guard !entry.media.isEmpty else { return await send(account: account, conversation: conversation, text: entry.text, operationID: entry.operationID) }
            return await MediaBackgroundTransfer.run(background, name: "ramflux.media.upload") {
                await media.send(account, conversation: conversation, groupID: entry.groupID, caption: entry.text, items: entry.media, operationID: entry.operationID)
            }
        }
    }
    public func retryOutbox(account: String, conversation: String, operationID: String) async -> [SendOutcome] {
        await queue.requeue(account, conversation, operationID: operationID)
        return await flushOutbox(account: account, conversation: conversation)
    }
    public func discardOutbox(account: String, conversation: String, operationID: String) async -> Bool {
        guard let entry = await queue.discard(account, conversation, operationID: operationID) else { return false }
        for item in entry.media { try? FileManager.default.removeItem(at: item.file) }
        return true
    }
    public func resumeAfterUnlock(account: String) async -> [SendOutcome] {
        var admitted: [SendOutcome] = []
        await retryRevokes(account)
        for conversation in await queue.pendingConversations(account) { admitted += await flushOutbox(account: account, conversation: conversation) }
        media.store.sweepOutbox(account, keeping: Set(await queue.allEntries(account).flatMap { $0.media.map(\.file.lastPathComponent) }))
        return admitted
    }
    public func sealForLock(account: String) async { await queue.seal(account) }
    public func purgeAccount(account: String) async {
        for entry in await queue.purge(account) { for item in entry.media { try? FileManager.default.removeItem(at: item.file) } }
        await media.cancelAll(account)
        media.store.purgeAccount(account)
    }
    public func shareCopy(account: String, file: URL, name: String) async -> URL? {
        let originals = media.store.originals(account).standardizedFileURL.path
        guard file.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent().path == originals else { return nil }
        let directory = media.store.share(account).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = directory.appendingPathComponent(MediaFileName.sanitized(name))
        do {
            try? FileManager.default.removeItem(at: media.store.share(account))
            try media.store.prepare(directory)
            try FileManager.default.copyItem(at: file, to: target)
            return target
        } catch { try? FileManager.default.removeItem(at: directory); return nil }
    }
    public func removeShareCopy(account: String) async { try? FileManager.default.removeItem(at: media.store.share(account)) }
    public func forward(account: String, text: String, attachments: [AttachmentRecord], to conversation: String, groupID: String?, operationID: String) async -> RepositoryResult<[SendOutcome]> {
        guard !attachments.isEmpty else { return await enqueue(account: account, conversation: conversation, text: text, operationID: operationID) }
        guard attachments.count <= MessagePage.maxAttachments, Self.identity(conversation), Self.identity(operationID) else { return .failure(.invalidInput) }
        let outbox = media.store.outbox(account)
        do { try media.store.prepare(outbox) } catch { return .failure(.localStorage) }
        var items: [MediaUpload] = []
        for attachment in attachments {
            var state = await media.state(account, attachment)
            if state == nil || state == .downloading { state = await download(account: account, attachment: attachment) }
            guard case .ready(let source)? = state else {
                for item in items { try? FileManager.default.removeItem(at: item.file) }
                return .failure(Self.forwardFailure(state ?? .idle))
            }
            let target = outbox.appendingPathComponent(UUID().uuidString)
            do { try FileManager.default.copyItem(at: source, to: target) } catch {
                for item in items { try? FileManager.default.removeItem(at: item.file) }
                return .failure(.localStorage)
            }
            let mime = attachment.mime.flatMap { (1...256).contains($0.utf8.count) ? $0 : nil } ?? "application/octet-stream"
            items.append(MediaUpload(file: target, fileName: MediaFileName.sanitized(attachment.name), mime: mime))
        }
        let result = await enqueueMedia(account: account, conversation: conversation, groupID: groupID, caption: text, items: items, operationID: operationID)
        if case .failure = result { for item in items { try? FileManager.default.removeItem(at: item.file) } }
        return result
    }
    private static func forwardFailure(_ state: MediaTransferState) -> AppFailure {
        switch state {
        case .expired: .typedRefusal("expired")
        case .removed: .typedRefusal("attachment_deleted")
        case .notAvailable: .typedRefusal("not_grantee")
        case .failed(let failure, _): failure
        default: .outcomeUnknown
        }
    }
    /// Revokes that failed earlier (offline, unknown outcome) are sent again, oldest first.
    private func retryRevokes(_ account: String) async {
        for message in await queue.revokes(account) {
            guard case .success = await media.revoke(account, message: message) else { return }
            await queue.removeRevoke(account, message: message)
        }
    }
    public func markRead(account: String, conversation: String, message: String) async -> RepositoryResult<Void> {
        guard Self.identity(conversation), Self.identity(message) else { return .failure(.invalidInput) }
        do {
            let reader = try await devices.device(account: account) { [gateway] in try ProxyGateway.text(try await gateway.call(.accountStatus, account: account), "device_id") }
            let body = try await gateway.call(.messageReceiptRead, account: account, body: .object(["conversation_id": .string(conversation), "message_id": .string(message), "reader_id": .string(reader)]))
            guard body["conversation_id"] == .string(conversation) else { throw AppFailure.invalidData }
            return .success(())
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func setTyping(account: String, conversation: String, active: Bool) async -> RepositoryResult<Void> {
        guard Self.identity(conversation) else { return .failure(.invalidInput) }
        let operation = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        do {
            if active { _ = try await gateway.call(.messageFocus, account: account, body: .object(["conversation_id": .string(conversation)])) }
            let send: JSONValue = .object(["conversationId": .string(conversation), "operationId": .string(Data(operation.utf8).base64EncodedString()), "content": .object(["typing": .object(["active": .bool(active)])])])
            _ = try await gateway.call(.messageSubmit, account: account, body: .object(["requestId": .string(operation), "accountId": .string(account), "send": send]), operationID: operation)
            if !active { _ = try await gateway.call(.messageFocus, account: account, body: .object(["conversation_id": .null])) }
            return .success(())
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func details(account: String, conversation: String, peerAnchor: String?) async -> RepositoryResult<ChatDetails> {
        guard Self.identity(conversation) else { return .failure(.invalidInput) }
        do {
            var row: JSONValue?
            var cursor: String?
            for _ in 0..<Self.directoryPages {
                var body: [String: JSONValue] = ["limit": .number(100)]
                if let cursor { body["cursor"] = .string(cursor) }
                let page = try await gateway.call(.conversationDirectory, account: account, body: .object(body))
                row = try ProxyGateway.rows(page, "conversations").first { $0["id"] == .string(conversation) }
                guard row == nil, let next = page["next_cursor"]?.string, !next.isEmpty else { break }
                cursor = next
            }
            var principal: String?, name: String?
            if let peerAnchor, !peerAnchor.isEmpty {
                let contacts = try ProxyGateway.rows(try await gateway.call(.contactList, account: account), "contacts")
                if let contact = contacts.first(where: { $0["root_commitment"] == .string(peerAnchor) }) {
                    principal = try ProxyGateway.text(contact, "principal_id"); name = contact["display_name"]?.string
                }
            }
            return .success(ChatDetails(muted: row?["muted"]?.bool, muteUntil: row.flatMap { ProxyGateway.integer($0["mute_until"]) }, peerPrincipal: principal, peerName: name))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func setMuted(account: String, conversation: String, muted: Bool, operationID: String) async -> RepositoryResult<Bool> {
        guard Self.identity(conversation), Self.identity(operationID) else { return .failure(.invalidInput) }
        do {
            let body: JSONValue = muted ? .object(["conversation_id": .string(conversation)]) : .object(["conversation_id": .string(conversation), "unmute": .bool(true)])
            let result = try await gateway.call(.conversationMute, account: account, body: body, operationID: operationID)
            guard result["conversation_id"] == .string(conversation) else { throw AppFailure.outcomeUnknown }
            let until = ProxyGateway.integer(result["mute_until"])
            return .success(until.map { $0 > Int64(Date().timeIntervalSince1970) } ?? false)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func mediaState(account: String, attachment: AttachmentRecord) async -> MediaTransferState? { await media.state(account, attachment) }
    public func download(account: String, attachment: AttachmentRecord) async -> MediaTransferState {
        guard Self.identity(attachment.messageID), (0..<MessagePage.maxAttachments).contains(attachment.index) else { return .failed(.invalidInput, retryable: false) }
        return await MediaBackgroundTransfer.run(background, name: "ramflux.media.download") { await media.download(account, attachment) }
    }
    public func cancelDownload(account: String, attachment: AttachmentRecord) async { await media.cancel(account, attachment) }
    public func mediaOutbox(account: String) async -> URL? {
        let directory = media.store.outbox(account)
        return (try? media.store.prepare(directory)) == nil ? nil : directory
    }
    public func revokeMedia(account: String, message: String) async -> RepositoryResult<Void> {
        guard Self.identity(message) else { return .failure(.invalidInput) }
        await queue.addRevoke(account, message: message)
        let result = await media.revoke(account, message: message)
        if case .success = result { await queue.removeRevoke(account, message: message) }
        return result
    }
    public func purgeAccountMedia(account: String) async { await media.cancelAll(account); media.store.purgeOriginals(account) }
    public func mediaUsage(account: String) async -> MediaUsage { media.store.usage(account) }
    public func mediaUsage(account: String, conversation: String) async -> Int64 { media.store.usage(account, conversation: conversation) }
    public func purgeConversationMedia(account: String, conversation: String) async {
        guard Self.identity(conversation) else { return }
        await media.cancelAll(account)
        media.store.purgeConversation(account, conversation: conversation)
    }
    /// Erased rows lose their local media at once (erase for everyone, local delete, expiry).
    private func purgeErased(_ account: String, _ records: [MessageRecord]) {
        for record in records where record.kind == .deleted { media.store.purge(account, message: record.id) }
    }
    public func draft(account: String, conversation: String) async -> String { await queue.draft(account, conversation) }
    public func saveDraft(account: String, conversation: String, text: String) async {
        guard text.utf8.count <= 65_536, Self.identity(conversation) else { return }
        await queue.saveDraft(account, conversation, text: text)
    }
    public func edit(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> {
        await mutate(.conversationEdit, account: account, conversation: conversation, message: message, operationID: operationID, text: text, extra: [:], states: ["submitted"])
    }
    public func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> {
        await mutate(.conversationReply, account: account, conversation: conversation, message: message, operationID: operationID, text: text, extra: [:], states: ["submitted"])
    }
    public func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) async -> RepositoryResult<Void> {
        guard ReactionToken.valid(token) else { return .failure(.invalidInput) }
        var extra: [String: JSONValue] = ["token": .string(token)]
        if remove { extra["remove"] = .bool(true) }
        return await mutate(.conversationReact, account: account, conversation: conversation, message: message, operationID: operationID, text: nil, extra: extra, states: ["submitted"])
    }
    public func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) async -> RepositoryResult<Void> {
        await mutate(.conversationDelete, account: account, conversation: conversation, message: message, operationID: operationID, text: nil, extra: ["scope": .string(scope.rawValue)], states: ["submitted", "local"])
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    public func typing(account: String, conversation: String) async -> AsyncStream<TypingEvent> {
        guard let transients else { return AsyncStream { $0.finish() } }
        let frames = await transients.transients(account: account)
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let task = Task {
                for await body in frames {
                    if let event = TypingEvent.parse(body), event.conversationID == conversation { continuation.yield(event) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func mutate(_ operation: SDKOperation, account: String, conversation: String, message: String, operationID: String, text: String?, extra: [String: JSONValue], states: Set<String>) async -> RepositoryResult<Void> {
        guard Self.identity(conversation), Self.identity(message), Self.identity(operationID) else { return .failure(.invalidInput) }
        if let text, !Self.usableText(text) { return .failure(.invalidInput) }
        var body: [String: JSONValue] = ["conversation_id": .string(conversation), "message_id": .string(message)]
        if let text { body["text"] = .string(text) }
        for (key, value) in extra { body[key] = value }
        let attempt = ChatMutationKey(kind: Self.kind(operation), message: message, text: text ?? "", token: extra["token"]?.string ?? "", remove: extra["remove"] == .bool(true), scope: extra["scope"]?.string ?? "")
        let request = body
        return await mutations.run(scope: Self.mutationScope(account, conversation), arguments: attempt, operationID: operationID) { [gateway] in
            do {
                let result = try await gateway.call(operation, account: account, body: .object(request), operationID: operationID)
                guard result["conversation_id"] == .string(conversation), let state = result["delivery_state"]?.string else { throw AppFailure.outcomeUnknown }
                let target = result["target_message_id"]?.string ?? result["message_id"]?.string
                guard target == message else { throw AppFailure.outcomeUnknown }
                if state == "failed" { throw Self.partial(result) ? AppFailure.outcomeUnknown : AppFailure.failed }
                guard states.contains(state) else { throw AppFailure.outcomeUnknown }
                return .success(())
            } catch { return .failure(AppFailure.map(error)) }
        }
    }
    static let pageSize = 50
    static let directoryPages = 100
    private static func scope(_ account: String, _ conversation: String) -> String { account + "\u{0}" + conversation }
    static func outcome(_ body: JSONValue, conversation: String) throws -> SendOutcome {
        guard body["conversation_id"] == .string(conversation), let state = body["delivery_state"]?.string.flatMap(SendOutcome.State.init(rawValue:)) else { throw AppFailure.outcomeUnknown }
        guard let message = body["message_id"]?.string, !message.isEmpty, message.utf8.count <= 65_536 else { throw AppFailure.outcomeUnknown }
        return SendOutcome(messageID: message, state: state)
    }
    private static func mutationScope(_ account: String, _ conversation: String) -> String { account + "\u{0}" + conversation + "\u{0}" + "mutation" }
    private static func kind(_ operation: SDKOperation) -> ChatMutationKey.Kind {
        switch operation {
        case .conversationEdit: .edit
        case .conversationReply: .reply
        case .conversationReact: .react
        default: .deletion
        }
    }
    /// A failed delivery that already reached one recipient must stay retryable on the same key.
    private static func partial(_ result: JSONValue) -> Bool {
        guard case .array(let rows) = result["deliveries"] else { return false }
        let submitted = rows.contains { $0["state"] == .string("submitted") }
        let failed = rows.contains { $0["state"] == .string("failed") }
        return submitted && failed
    }
    private static func usableText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 65_536
    }
    private static func identity(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 256 }
}
public struct UnavailableChatRepository: ChatRepository {
    public init() {}
    public func unavailable(_ capability: ChatCapability) -> AppFailure { ChatUnavailable.failure(capability) }
    public func messages(account: String, conversation: String, before: MessageCursor?) async -> RepositoryResult<MessageWindowPage> { .failure(.sdkUnavailable) }
    public func changes(account: String, conversation: String, after: UInt64) async -> RepositoryResult<MessageChangeBatch> { .failure(.sdkUnavailable) }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> { .failure(.sdkUnavailable) }
    public func enqueue(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<[SendOutcome]> { .failure(.sdkUnavailable) }
    public func edit(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}

/// Defaults for repositories without these capabilities: nothing queued, nothing retained, and
/// typed unavailable results instead of invented state.
public extension ChatRepository {
    func sendState(account: String, conversation: String) async -> PendingChatSend? { nil }
    func mutationState(account: String, conversation: String) async -> PendingChatMutation? { nil }
    func changes(account: String, conversation: String, after: UInt64) async -> RepositoryResult<MessageChangeBatch> { .failure(.sdkUnavailable) }
    func outbox(account: String, conversation: String) async -> [OutboxEntry] { [] }
    func flushOutbox(account: String, conversation: String) async -> [SendOutcome] { [] }
    func retryOutbox(account: String, conversation: String, operationID: String) async -> [SendOutcome] { [] }
    func discardOutbox(account: String, conversation: String, operationID: String) async -> Bool { false }
    func markRead(account: String, conversation: String, message: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    func setTyping(account: String, conversation: String, active: Bool) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    func details(account: String, conversation: String, peerAnchor: String?) async -> RepositoryResult<ChatDetails> { .failure(unavailable(.details)) }
    func setMuted(account: String, conversation: String, muted: Bool, operationID: String) async -> RepositoryResult<Bool> { .failure(unavailable(.details)) }
    func draft(account: String, conversation: String) async -> String { "" }
    func saveDraft(account: String, conversation: String, text: String) async {}
    func mediaState(account: String, attachment: AttachmentRecord) async -> MediaTransferState? { nil }
    func download(account: String, attachment: AttachmentRecord) async -> MediaTransferState { .failed(unavailable(.attachmentTransfer), retryable: false) }
    func cancelDownload(account: String, attachment: AttachmentRecord) async {}
    func mediaOutbox(account: String) async -> URL? { nil }
    func enqueueMedia(account: String, conversation: String, groupID: String?, caption: String, items: [MediaUpload], operationID: String) async -> RepositoryResult<[SendOutcome]> { .failure(unavailable(.attachmentTransfer)) }
    func revokeMedia(account: String, message: String) async -> RepositoryResult<Void> { .failure(unavailable(.attachmentTransfer)) }
    func purgeAccountMedia(account: String) async {}
    func mediaUsage(account: String, conversation: String) async -> Int64 { 0 }
    func purgeConversationMedia(account: String, conversation: String) async {}
    func resumeAfterUnlock(account: String) async -> [SendOutcome] { [] }
    func sealForLock(account: String) async {}
    func purgeAccount(account: String) async {}
    func typing(account: String, conversation: String) async -> AsyncStream<TypingEvent> { AsyncStream { $0.finish() } }
    func shareCopy(account: String, file: URL, name: String) async -> URL? { nil }
    func removeShareCopy(account: String) async {}
    func forward(account: String, text: String, attachments: [AttachmentRecord], to conversation: String, groupID: String?, operationID: String) async -> RepositoryResult<[SendOutcome]> { .failure(unavailable(.attachmentTransfer)) }
    func mediaUsage(account: String) async -> MediaUsage { MediaUsage(originals: 0, outbox: 0) }
}
enum ChatUnavailable {
    static func failure(_ capability: ChatCapability) -> AppFailure {
        switch capability {
        case .calls: .unavailableResource("chat.unavailable.calls")
        case .details: .unavailableResource("chat.unavailable.details")
        case .attachmentTransfer: .unavailableResource("chat.unavailable.attachmentTransfer")
        }
    }
}
/// The local device id, read once per account from `account.status`.
actor OwnDeviceCache {
    private var devices: [String: String] = [:]
    func device(account: String, read: @Sendable () async throws -> String) async throws -> String {
        if let device = devices[account] { return device }
        let device = try await read(); devices[account] = device; return device
    }
}
