// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public struct NativeCallsRepository: CallsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    private let signals = RetainedMutation<CallSignalArguments, CallRecord>()
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func list(account: String) async -> RepositoryResult<[CallRecord]> {
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
        await signals.run(scope: account, arguments: CallSignalArguments(expected: attempt.expected, signal: attempt.signal), operationID: attempt.operationID) {
            let current: [CallRecord]
            switch await list(account: account) { case .success(let rows): current = rows; case .failure(let failure): return .failure(failure) }
            guard attempt.expected.canHangup, (attempt.signal != .decline || attempt.expected.canDecline),
                  let selected = current.first(where: { $0.id == attempt.expected.id }), selected.peerID == attempt.expected.peerID,
                  selected.conversationID == attempt.expected.conversationID, selected.direction == attempt.expected.direction else { return .failure(.invalidInput) }
            // A fresh authoritative terminal row proves the local call no longer needs ending.
            // Return its actual reason; never claim our uncertain action caused that ending.
            if selected.phase == .ended, selected.sequence >= attempt.expected.sequence { return .success(selected) }
            guard selected == attempt.expected else { return .failure(.busy) }
            let response: JSONValue
            do {
                response = try await gateway.call(attempt.signal == .decline ? .callReject : .callHangup, account: account,
                    body: .object(["call_id": .string(attempt.expected.id)]), operationID: attempt.operationID)
            } catch { return .failure(AppFailure.map(error)) }
            do {
                let row = try Self.record(response)
                guard row.id == attempt.expected.id, row.conversationID == attempt.expected.conversationID,
                      row.peerID == attempt.expected.peerID, row.direction == attempt.expected.direction,
                      row.phase == .ended, row.sequence >= attempt.expected.sequence else { throw AppFailure.outcomeUnknown }
                return .success(row)
            } catch { return .failure(.outcomeUnknown) }
        }
    }
    // The phone has no media engine. Never create an invite/answer or consume its one-shot key
    // merely to render a call screen. Signaling history and explicit end actions remain real.
    public func start(account: String, conversation: String) async -> RepositoryResult<CallRecord> { .failure(audioUnavailable()) }
    public func answer(account: String, expected: CallRecord) async -> RepositoryResult<CallRecord> { .failure(audioUnavailable()) }
    public func audioUnavailable() -> AppFailure { .unavailableResource("calls.audioUnavailable") }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    private static func record(_ row: JSONValue) throws -> CallRecord {
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
