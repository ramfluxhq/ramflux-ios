// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct CallsRepositoryTests {
    private func row(phase: String = "incoming_ringing", seq: UInt64 = UInt64.max, peer: String = "peer") -> JSONValue {
        .object(["call_id": .string("c"), "conversation_id": .string("thread"), "peer_id": .string(peer), "direction": .string("incoming"), "state": .string(phase), "seq": .unsigned(seq), "media_generation": .unsigned(UInt64.max), "created_at": .number(1_800_000_000), "answered_at": .null, "ended_at": phase == "ended" ? .number(1_800_000_010) : .null, "end_reason": phase == "ended" ? .string("declined") : .null, "failure_reason": .string("daemon_restarted"), "peer_reason": .string("relay_unavailable")])
    }
    private func repository(_ fixture: ProxyTransport) -> NativeCallsRepository {
        let client = RamfluxClient(transport: fixture); return NativeCallsRepository(client: client, updates: NativeUpdateSource(client: client))
    }
    @Test func historyPreservesExactVersionsAndDistinctFailureOrigins() async {
        let fixture = ProxyTransport { _ in .object(["calls": .array([row(phase: "future_phase")])]) }
        guard case .success(let rows) = await repository(fixture).list(account: "a"), let call = rows.first else { Issue.record("Call list failed"); return }
        #expect(call.sequence == UInt64.max); #expect(call.mediaGeneration == UInt64.max)
        #expect(call.phase == .unknown); #expect(!call.canHangup)
        #expect(call.failureReason == .daemonRestarted); #expect(call.peerReason == .relayUnavailable)
    }
    @Test func declineUsesRealSignalingMethodAndStableKeyWithoutMediaAccess() async {
        let fixture = ProxyTransport { request in
            switch request.method {
            case "call.list": return .object(["calls": .array([row()])])
            case "call.reject":
                #expect(request.body == .object(["call_id": .string("c")])); #expect(request.operationID?.rawValue == "original")
                return row(phase: "ended")
            default: Issue.record("Unexpected signaling/media operation"); return .null
            }
        }
        let repo = repository(fixture)
        guard case .success(let rows) = await repo.list(account: "a"), let selected = rows.first else { Issue.record("No call"); return }
        guard case .success(let ended) = await repo.signal(account: "a", attempt: CallSignalAttempt(expected: selected, signal: .decline, operationID: "original")) else { Issue.record("Decline failed"); return }
        #expect(ended.phase == .ended); #expect(ended.endReason == "declined"); #expect(await repo.pending(account: "a") == nil)
        #expect(await repo.start(account: "a", conversation: "thread") == .failure(repo.audioUnavailable()))
        #expect(await repo.answer(account: "a", expected: selected) == .failure(repo.audioUnavailable()))
        #expect(fixture.calls.withLock { $0.allSatisfy { ["call.list", "call.reject"].contains($0.method) } })
    }
    @Test func staleSelectionNeverEndsAnotherPeerOrVersion() async {
        let fixture = ProxyTransport { _ in .object(["calls": .array([row(seq: 3)])]) }
        let actual = repository(fixture)
        let expected = CallRecord(id: "c", conversationID: "thread", peerID: "peer", direction: .incoming, phase: .incomingRinging, sequence: 2, createdAt: 1_800_000_000)
        #expect(await actual.signal(account: "a", attempt: CallSignalAttempt(expected: expected, signal: .decline, operationID: "stale")) == .failure(.busy))
        #expect(fixture.calls.withLock { $0.allSatisfy { $0.method == "call.list" } })
    }
    @Test func malformedAcknowledgementRemainsUnknownAndTerminalReadResolvesWithoutNewMutation() async {
        let fixture = ProxyTransport { request in request.method == "call.list" ? .object(["calls": .array([row()])]) : .object([:]) }
        let repo = repository(fixture)
        guard case .success(let rows) = await repo.list(account: "a"), let selected = rows.first else { Issue.record("No call"); return }
        let attempt = CallSignalAttempt(expected: selected, signal: .hangup, operationID: "retained")
        #expect(await repo.signal(account: "a", attempt: attempt) == .failure(.outcomeUnknown)); #expect(await repo.pending(account: "a") == attempt)
        let terminalFixture = ProxyTransport { _ in .object(["calls": .array([row(phase: "ended")])]) }
        let terminal = repository(terminalFixture)
        guard case .success(let ended) = await terminal.signal(account: "a", attempt: attempt) else { Issue.record("Terminal state not reconciled"); return }
        #expect(ended.phase == .ended); #expect(terminalFixture.calls.withLock { $0.count == 1 && $0.first?.method == "call.list" })
    }
}
