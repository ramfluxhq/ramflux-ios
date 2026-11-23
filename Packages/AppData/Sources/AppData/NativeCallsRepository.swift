// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public struct NativeCallsRepository: CallsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    private let engine: any CallMediaEngine
    private let signals = RetainedMutation<CallSignalArguments, CallRecord>()
    private let handoff = CallMediaHandoff()
    public init(client: RamfluxClient, updates: NativeUpdateSource, engine: any CallMediaEngine = RefusingCallMediaEngine()) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates; self.engine = engine
    }
    public func mediaAvailability() -> CallMediaAvailability { engine.availability() }
    public func history(account: String, cursor: String?) async -> RepositoryResult<CallHistoryPage> {
        // `call.list` has no cursor: the whole (bounded) history is the first page.
        guard cursor == nil else { return .failure(.invalidInput) }
        switch await list(account: account) {
        case .success(let rows): return .success(CallHistoryPage(rows: rows, nextCursor: nil))
        case .failure(let failure): return .failure(failure)
        }
    }
    private func list(account: String) async -> RepositoryResult<[CallRecord]> {
        do {
            let rows = try ProxyGateway.rows(await gateway.call(.callList, account: account), "calls").map(Self.record)
            guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }; return .success(rows)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func pending(account: String) async -> CallSignalAttempt? {
        guard let entry = await signals.snapshot(scope: account), entry.unresolved else { return nil }
        return CallSignalAttempt(expected: entry.arguments.expected, signal: entry.arguments.signal, operationID: entry.operationID)
    }
    public func signal(account: String, attempt: CallSignalAttempt) async -> RepositoryResult<CallRecord> {
        // Answering connects this phone's media: never ring back a caller the phone cannot hear.
        if attempt.signal == .answer, case .unavailable(let failure) = engine.availability() { return .failure(failure) }
        return await signals.run(scope: account, arguments: CallSignalArguments(expected: attempt.expected, signal: attempt.signal), operationID: attempt.operationID) {
            let current: [CallRecord]
            switch await list(account: account) { case .success(let rows): current = rows; case .failure(let failure): return .failure(failure) }
            guard attempt.expected.canHangup, (attempt.signal == .hangup || attempt.expected.canDecline),
                  let selected = current.first(where: { $0.id == attempt.expected.id }), selected.peerID == attempt.expected.peerID,
                  selected.conversationID == attempt.expected.conversationID, selected.direction == attempt.expected.direction else { return .failure(.invalidInput) }
            // A fresh authoritative terminal row proves the local call no longer needs ending.
            // Return its actual reason; never claim our uncertain action caused that ending.
            if selected.phase == .ended, selected.sequence >= attempt.expected.sequence { return .success(selected) }
            // A retried answer whose first attempt landed finds the call already answered.
            if attempt.signal == .answer, [.connecting, .active].contains(selected.phase), selected.sequence >= attempt.expected.sequence { return .success(selected) }
            guard selected == attempt.expected else { return .failure(.busy) }
            let operation: SDKOperation = switch attempt.signal { case .decline: .callReject; case .hangup: .callHangup; case .answer: .callAnswer }
            let response: JSONValue
            do {
                response = try await gateway.call(operation, account: account, body: .object(["call_id": .string(attempt.expected.id)]), operationID: attempt.operationID)
            } catch { return .failure(AppFailure.map(error)) }
            do {
                let row = try Self.record(response)
                let settled: Bool = attempt.signal == .answer ? [.connecting, .active, .ended].contains(row.phase) : row.phase == .ended
                guard row.id == attempt.expected.id, row.conversationID == attempt.expected.conversationID,
                      row.peerID == attempt.expected.peerID, row.direction == attempt.expected.direction,
                      settled, row.sequence >= attempt.expected.sequence else { throw AppFailure.outcomeUnknown }
                return .success(row)
            } catch { return .failure(.outcomeUnknown) }
        }
    }
    public func start(account: String, conversation: String) async -> RepositoryResult<CallRecord> {
        // A real invite rings the peer: send it only when this phone can carry the call.
        if case .unavailable(let failure) = engine.availability() { return .failure(failure) }
        guard !conversation.isEmpty, conversation.utf8.count <= 512 else { return .failure(.invalidInput) }
        let response: JSONValue
        do { response = try await gateway.call(.callInvite, account: account, body: .object(["conversation_id": .string(conversation)]), operationID: UUID().uuidString) }
        catch { return .failure(AppFailure.map(error)) }
        // The daemon refuses a second invite while any call is live, so an uncertain invite is
        // reconciled from the history and `call.changed`, never by inviting again.
        guard let row = try? Self.record(response), row.conversationID == conversation, row.direction == .outgoing, row.phase != .unknown else { return .failure(.outcomeUnknown) }
        return .success(row)
    }
    public func connectMedia(account: String, call: CallRecord) async -> RepositoryResult<Void> {
        if case .unavailable(let failure) = engine.availability() { return .failure(failure) }
        guard call.phase == .active else { return .failure(.invalidInput) }
        // The SDK returns the material once per call; a lost read requires a new call.
        guard await handoff.claim(account: account, callID: call.id) else { return .success(()) }
        let reply: SecretBytes
        do {
            reply = try await gateway.proxy.callMediaSession(context: gateway.context(.callMediaSession, account: account), body: .object(["call_id": .string(call.id)]))
        } catch { return .failure(AppFailure.map(error)) }
        let session: CallMediaSession
        do { session = try CallMediaSession.sealed(reply, call: call) } catch { return .failure(.invalidData) }
        return await engine.start(session)
    }
    public func control(_ control: CallMediaControl, callID: String) async -> RepositoryResult<Void> { await engine.control(control, callID: callID) }
    public func stopMedia(callID: String) async { await engine.stop(callID: callID) }
    public func audioSession(active: Bool) async { await engine.audioSession(active: active) }
    public func mediaEvents() -> AsyncStream<CallMediaEvent> { engine.events() }
    @MainActor public func attachVideo(_ surface: (any CallVideoSurface)?, slot: CallVideoSlot, callID: String) { engine.attach(surface, slot: slot, callID: callID) }
    /// The shared fan-out: its filter names `call.changed` explicitly (never `*`).
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    static func record(_ row: JSONValue) throws -> CallRecord {
        guard let sequence = unsigned(row["seq"]), let generation = unsigned(row["media_generation"]),
              let created = ProxyGateway.integer(row["created_at"]), (0...253402300799).contains(created) else { throw AppFailure.invalidData }
        func time(_ key: String) throws -> Int64? {
            guard let value = row[key], value != .null else { return nil }
            guard let time = ProxyGateway.integer(value), (0...253402300799).contains(time) else { throw AppFailure.invalidData }; return time
        }
        let phase = CallPhase(rawValue: try ProxyGateway.text(row, "state")) ?? .unknown
        let direction = CallDirection(rawValue: try ProxyGateway.text(row, "direction")) ?? .unknown
        return CallRecord(id: try ProxyGateway.text(row, "call_id"), conversationID: try ProxyGateway.text(row, "conversation_id"), peerID: try ProxyGateway.text(row, "peer_id"), direction: direction, phase: phase,
            endReason: row["end_reason"]?.string, failureReason: row["failure_reason"]?.string.map { CallFailureReason(rawValue: $0) ?? .unknown }, peerReason: row["peer_reason"]?.string.map { CallFailureReason(rawValue: $0) ?? .unknown }, sequence: sequence, mediaGeneration: generation, createdAt: created, answeredAt: try time("answered_at"), endedAt: try time("ended_at"))
    }
    private static func unsigned(_ value: JSONValue?) -> UInt64? { switch value { case .unsigned(let value): value; case .number(let value): UInt64(exactly: value); case .string(let value): UInt64(value); default: nil } }
}
