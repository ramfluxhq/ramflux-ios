// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// A message the user sent that the SDK has not admitted yet. It is shown in the timeline as a
/// local row with its state, never as a delivered message. A media send carries its staged
/// outbox files; `text` is then the caption (possibly empty).
public struct OutboxEntry: Identifiable, Sendable, Equatable, CustomStringConvertible {
    public enum State: Sendable, Equatable {
        /// Waiting for its turn or for the connection; retried automatically with the same key.
        case queued
        /// In flight. The SDK reports no upload bytes, so this is indeterminate.
        case sending
        /// The SDK answered with a definite failure; only an explicit retry sends it again.
        case failed(AppFailure)
    }
    public var description: String { "OutboxEntry(<redacted>)" }
    public var id: String { operationID }
    public let operationID: String
    public let text: String
    /// Unix seconds when the user pressed send; used for the local time label only.
    public let created: Int64
    public var state: State
    /// Set for a group conversation's media send (`attachment.prepare.begin` kind `group`).
    public let groupID: String?
    /// Staged files in the account's protected media outbox, in send order (at most 16).
    public let media: [MediaUpload]
    public init(operationID: String, text: String, created: Int64, state: State, groupID: String? = nil, media: [MediaUpload] = []) {
        self.operationID = operationID; self.text = text; self.created = created; self.state = state; self.groupID = groupID; self.media = media
    }
}

/// Per-account unsent chat state: the per-conversation FIFO of unadmitted sends, composer drafts
/// and revokes to retry. It is restored from the sealed vault on first use (after unlock) and
/// written back after every change; drafts are written after a short pause so typing does not
/// write on every key. One entry per conversation is in flight at a time; the SDK makes
/// `conversation.send` idempotent by operation id, so a retry or a resumed send reuses the key.
/// Without a vault (tests, unavailable store) everything stays in process memory.
actor ChatOutbox {
    private struct Account {
        var queues: [String: [OutboxEntry]] = [:]
        var drafts: [String: String] = [:]
        var revokes: [String] = []
    }
    private let vault: ChatVault?
    private let draftPause: Duration
    private var accounts: [String: Account] = [:]
    private var loading: [String: Task<Account, Never>] = [:]
    private var flushing: Set<String> = []
    private var draftWrites: [String: Task<Void, Never>] = [:]
    init(vault: ChatVault? = nil, draftPause: Duration = .milliseconds(400)) { self.vault = vault; self.draftPause = draftPause }

    private func account(_ id: String) async -> Account {
        if let known = accounts[id] { return known }
        if let running = loading[id] { return await running.value }
        let task = Task { [vault] in
            guard let vault else { return Account() }
            let snapshot = await vault.load(id)
            var restored = Account(drafts: snapshot.drafts, revokes: snapshot.revokes)
            for (conversation, entries) in snapshot.outbox { restored.queues[conversation] = entries.map { vault.decode($0, account: id) } }
            return restored
        }
        loading[id] = task
        let value = await task.value
        loading[id] = nil
        if let known = accounts[id] { return known }
        accounts[id] = value
        return value
    }
    private func update(_ id: String, persist: Bool = true, _ change: (inout Account) -> Void) async {
        _ = await account(id)
        change(&accounts[id, default: Account()])
        if persist { await write(id) }
    }
    private func snapshot(_ id: String) -> ChatVaultSnapshot {
        guard let state = accounts[id] else { return ChatVaultSnapshot() }
        var outbox: [String: [ChatVaultSnapshot.Entry]] = [:]
        for (conversation, entries) in state.queues where !entries.isEmpty { outbox[conversation] = entries.map(ChatVault.encode) }
        return ChatVaultSnapshot(outbox: outbox, drafts: state.drafts, revokes: state.revokes)
    }
    /// A failed write (for example while the device is locked and the file is unreadable) keeps
    /// the memory copy authoritative; the next change writes again.
    private func write(_ id: String) async {
        draftWrites[id]?.cancel(); draftWrites[id] = nil
        guard let vault else { return }
        try? await vault.save(id, snapshot(id))
    }

    // MARK: Queue

    func entries(_ account: String, _ conversation: String) async -> [OutboxEntry] { await self.account(account).queues[conversation] ?? [] }

    func allEntries(_ account: String) async -> [OutboxEntry] { await self.account(account).queues.values.flatMap { $0 } }

    /// Conversations with entries waiting to be sent automatically.
    func pendingConversations(_ account: String) async -> [String] {
        await self.account(account).queues.filter { $0.value.contains { $0.state == .queued } }.keys.sorted()
    }

    func enqueue(_ account: String, _ conversation: String, entry: OutboxEntry) async {
        guard !(await self.account(account).queues[conversation] ?? []).contains(where: { $0.operationID == entry.operationID }) else { return }
        await update(account) { $0.queues[conversation, default: []].append(entry) }
    }

    /// Removes an entry that is not in flight and returns it, so the caller can erase its files.
    func discard(_ account: String, _ conversation: String, operationID: String) async -> OutboxEntry? {
        guard let entry = await self.account(account).queues[conversation]?.first(where: { $0.operationID == operationID }), entry.state != .sending else { return nil }
        await update(account) { $0.queues[conversation]?.removeAll { $0.operationID == operationID } }
        return entry
    }

    func requeue(_ account: String, _ conversation: String, operationID: String) async {
        guard let index = await self.account(account).queues[conversation]?.firstIndex(where: { $0.operationID == operationID }),
              case .failed(let failure)? = accounts[account]?.queues[conversation]?[index].state, failure != .localStorage else { return }
        await update(account) { $0.queues[conversation]?[index].state = .queued }
    }

    /// Sends queued entries oldest first until one cannot be admitted. An offline or unknown
    /// outcome stops the flush and keeps the entry queued; a definite failure marks the entry
    /// failed and lets the next one go. Admitted entries are removed and the vault rewritten.
    func flush(_ account: String, _ conversation: String, send: @Sendable (OutboxEntry) async -> RepositoryResult<SendOutcome>) async -> [SendOutcome] {
        let scope = account + "\u{0}" + conversation
        _ = await self.account(account)
        guard flushing.insert(scope).inserted else { return [] }
        defer { flushing.remove(scope) }
        var admitted: [SendOutcome] = []
        while let index = accounts[account]?.queues[conversation]?.firstIndex(where: { $0.state == .queued }), let entry = accounts[account]?.queues[conversation]?[index] {
            accounts[account]?.queues[conversation]?[index].state = .sending
            let result = await send(entry)
            guard let position = accounts[account]?.queues[conversation]?.firstIndex(where: { $0.operationID == entry.operationID }) else { continue }
            switch result {
            case .success(let outcome) where outcome.state == .submitted:
                accounts[account]?.queues[conversation]?.remove(at: position); admitted.append(outcome)
                await write(account)
            case .success:
                accounts[account]?.queues[conversation]?[position].state = .failed(.unavailableResource("chat.send.deliveryFailed"))
                await write(account)
            case .failure(let error) where error == .offline || error == .outcomeUnknown || error == .busy:
                accounts[account]?.queues[conversation]?[position].state = .queued
                return admitted
            case .failure(let error):
                accounts[account]?.queues[conversation]?[position].state = .failed(error)
                await write(account)
            }
        }
        return admitted
    }

    // MARK: Drafts

    func draft(_ account: String, _ conversation: String) async -> String { await self.account(account).drafts[conversation] ?? "" }

    func saveDraft(_ account: String, _ conversation: String, text: String) async {
        await update(account, persist: false) { $0.drafts[conversation] = text.isEmpty ? nil : text }
        draftWrites[account]?.cancel()
        let pause = draftPause
        draftWrites[account] = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            await self?.write(account)
        }
    }

    // MARK: Revokes

    func revokes(_ account: String) async -> [String] { await self.account(account).revokes }
    func addRevoke(_ account: String, message: String) async {
        guard !(await self.account(account).revokes.contains(message)) else { return }
        await update(account) { $0.revokes.append(message) }
    }
    func removeRevoke(_ account: String, message: String) async { await update(account) { $0.revokes.removeAll { $0 == message } } }

    // MARK: Lifecycle

    /// Writes pending changes and drops the account from memory; the next use restores it.
    func seal(_ account: String) async {
        if accounts[account] != nil { await write(account) }
        accounts[account] = nil
    }

    /// Drops everything of the account: memory, the sealed file and its keychain key.
    func purge(_ account: String) async -> [OutboxEntry] {
        let entries = await self.account(account).queues.values.flatMap { $0 }
        draftWrites[account]?.cancel(); draftWrites[account] = nil
        accounts[account] = nil
        await vault?.erase(account)
        return entries
    }
}
