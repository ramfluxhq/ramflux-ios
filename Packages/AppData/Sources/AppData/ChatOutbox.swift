// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// A message the user sent that the SDK has not admitted yet. It is shown in the timeline as a
/// local row with its state, never as a delivered message.
public struct OutboxEntry: Identifiable, Sendable, Equatable, CustomStringConvertible {
    public enum State: Sendable, Equatable {
        /// Waiting for its turn or for the connection; retried automatically with the same key.
        case queued
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
    public init(operationID: String, text: String, created: Int64, state: State) { self.operationID = operationID; self.text = text; self.created = created; self.state = state }
}

/// Per-conversation FIFO of unadmitted sends, held in process memory only (never persisted, so
/// no plaintext is written outside the SDK's protected store). One entry is in flight at a time;
/// the SDK makes `conversation.send` idempotent by operation id, so a retry reuses the key.
actor ChatOutbox {
    private var queues: [String: [OutboxEntry]] = [:]
    private var flushing: Set<String> = []

    func entries(_ scope: String) -> [OutboxEntry] { queues[scope] ?? [] }

    func enqueue(_ scope: String, entry: OutboxEntry) {
        guard !(queues[scope] ?? []).contains(where: { $0.operationID == entry.operationID }) else { return }
        queues[scope, default: []].append(entry)
    }

    func discard(_ scope: String, operationID: String) -> Bool {
        guard let entry = queues[scope]?.first(where: { $0.operationID == operationID }), entry.state != .sending else { return false }
        queues[scope]?.removeAll { $0.operationID == operationID }
        return true
    }

    func requeue(_ scope: String, operationID: String) {
        guard let index = queues[scope]?.firstIndex(where: { $0.operationID == operationID }), case .failed = queues[scope]?[index].state else { return }
        queues[scope]?[index].state = .queued
    }

    func clear(_ scope: String) { queues[scope] = nil }

    /// Sends queued entries oldest first until one cannot be admitted. An offline or unknown
    /// outcome stops the flush and keeps the entry queued; a definite failure marks the entry
    /// failed and lets the next one go.
    func flush(_ scope: String, send: @Sendable (OutboxEntry) async -> RepositoryResult<SendOutcome>) async -> [SendOutcome] {
        guard flushing.insert(scope).inserted else { return [] }
        defer { flushing.remove(scope) }
        var admitted: [SendOutcome] = []
        while let index = queues[scope]?.firstIndex(where: { $0.state == .queued }), let entry = queues[scope]?[index] {
            queues[scope]?[index].state = .sending
            let result = await send(entry)
            guard let position = queues[scope]?.firstIndex(where: { $0.operationID == entry.operationID }) else { continue }
            switch result {
            case .success(let outcome) where outcome.state == .submitted:
                queues[scope]?.remove(at: position); admitted.append(outcome)
            case .success:
                queues[scope]?[position].state = .failed(.unavailableResource("chat.send.deliveryFailed"))
            case .failure(let error) where error == .offline || error == .outcomeUnknown || error == .busy:
                queues[scope]?[position].state = .queued
                return admitted
            case .failure(let error):
                queues[scope]?[position].state = .failed(error)
            }
        }
        return admitted
    }
}

/// Unsent composer text per conversation, in process memory only. It survives the chat screen
/// being concealed or rebuilt while the app is backgrounded, and is dropped with the process.
actor ChatDrafts {
    private var drafts: [String: String] = [:]
    func draft(_ scope: String) -> String { drafts[scope] ?? "" }
    func save(_ scope: String, text: String) { drafts[scope] = text.isEmpty ? nil : text }
    func clearAccount(_ prefix: String) { drafts = drafts.filter { !$0.key.hasPrefix(prefix) } }
}
