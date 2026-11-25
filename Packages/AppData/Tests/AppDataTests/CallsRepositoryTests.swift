// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import RamfluxCore
@testable import AppData

/// Records what the repository hands to the engine; reads the material once like a real engine.
final class FakeCallMediaEngine: CallMediaEngine {
    let available: Bool
    let started = Mutex<[String]>([])
    let materials = Mutex<[Data]>([])
    let controls = Mutex<[CallMediaControl]>([])
    init(available: Bool = true) { self.available = available }
    func availability() -> CallMediaAvailability { available ? .available(CallMediaCapabilities(audio: true, video: true, cameraSwitch: true, speakerRoute: true)) : .unavailable(.unsupported) }
    func start(_ session: CallMediaSession) async -> RepositoryResult<Void> {
        do {
            let bytes = try session.consume { Data($0) }
            materials.withLock { $0.append(bytes) }; started.withLock { $0.append(session.callID) }; return .success(())
        } catch { return .failure(.invalidData) }
    }
    func stop(callID: String) async {}
    func control(_ control: CallMediaControl, callID: String) async -> RepositoryResult<Void> { controls.withLock { $0.append(control) }; return .success(()) }
    func audioSession(active: Bool) async {}
    func events() -> AsyncStream<CallMediaEvent> { AsyncStream { $0.finish() } }
    @MainActor func attach(_ surface: (any CallVideoSurface)?, slot: CallVideoSlot, callID: String) {}
}

@Suite(.timeLimit(.minutes(1))) struct CallsRepositoryTests {
    private func row(phase: String = "incoming_ringing", seq: UInt64 = UInt64.max, peer: String = "peer", direction: String = "incoming") -> JSONValue {
        .object(["call_id": .string("c"), "conversation_id": .string("thread"), "peer_id": .string(peer), "direction": .string(direction), "state": .string(phase), "seq": .unsigned(seq), "media_generation": .unsigned(UInt64.max), "created_at": .number(1_800_000_000), "answered_at": .null, "ended_at": phase == "ended" ? .number(1_800_000_010) : .null, "end_reason": phase == "ended" ? .string("declined") : .null, "failure_reason": .string("daemon_restarted"), "peer_reason": .string("relay_unavailable")])
    }
    private static let session: JSONValue = .object(["relay": .object(["endpoint": .string("relay.example:4000"), "token": .string("t"), "lease_id": .string("l"), "side": .number(1), "rebind_key": .string("r")]),
        "sframe": .object(["cipher_suite": .number(5), "send": .object(["kid": .number(1), "base_key": .string("s")]), "receive": .object(["kid": .number(0), "base_key": .string("k")])])])
    private func repository(_ fixture: ProxyTransport, engine: any CallMediaEngine = RefusingCallMediaEngine()) -> NativeCallsRepository {
        let client = RamfluxClient(transport: fixture); return NativeCallsRepository(client: client, updates: NativeUpdateSource(client: client), engine: engine)
    }
    /// `RepositoryResult<Void>` is not Equatable: compare its failure (nil on success).
    private func failure(_ result: RepositoryResult<Void>) -> AppFailure? { if case .failure(let value) = result { value } else { nil } }
    private func first(_ repo: NativeCallsRepository) async -> CallRecord? {
        guard case .success(let page) = await repo.history(account: "a", cursor: nil) else { return nil }; return page.rows.first
    }
    @Test func historyPreservesExactVersionsAndDistinctFailureOrigins() async {
        let fixture = ProxyTransport { _ in .object(["calls": .array([row(phase: "future_phase")])]) }
        let repo = repository(fixture)
        guard case .success(let page) = await repo.history(account: "a", cursor: nil), let call = page.rows.first else { Issue.record("Call list failed"); return }
        #expect(page.nextCursor == nil)
        #expect(call.sequence == UInt64.max); #expect(call.mediaGeneration == UInt64.max)
        #expect(call.phase == .unknown); #expect(!call.canHangup)
        #expect(call.failureReason == .daemonRestarted); #expect(call.peerReason == .relayUnavailable)
        #expect(await repo.history(account: "a", cursor: "next") == .failure(.invalidInput))
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
        guard let selected = await first(repo) else { Issue.record("No call"); return }
        guard case .success(let ended) = await repo.signal(account: "a", attempt: CallSignalAttempt(expected: selected, signal: .decline, operationID: "original")) else { Issue.record("Decline failed"); return }
        #expect(ended.phase == .ended); #expect(ended.endReason == "declined"); #expect(await repo.pending(account: "a") == nil)
        #expect(fixture.calls.withLock { $0.allSatisfy { ["call.list", "call.reject"].contains($0.method) } })
    }
    @Test func refusingEngineNeverInvitesAnswersOrReadsMedia() async {
        let fixture = ProxyTransport { request in
            guard request.method == "call.list" else { Issue.record("Media-dependent call sent: \(request.method)"); return .null }
            return .object(["calls": .array([row()])])
        }
        let repo = repository(fixture)
        guard let selected = await first(repo) else { Issue.record("No call"); return }
        #expect(repo.mediaAvailability().failure == repo.audioUnavailable())
        #expect(await repo.start(account: "a", conversation: "thread") == .failure(repo.audioUnavailable()))
        #expect(await repo.signal(account: "a", attempt: CallSignalAttempt(expected: selected, signal: .answer, operationID: "answer")) == .failure(repo.audioUnavailable()))
        let active = CallRecord(id: "c", conversationID: "thread", peerID: "peer", direction: .incoming, phase: .active, sequence: 9, createdAt: 1_800_000_000)
        #expect(failure(await repo.connectMedia(account: "a", call: active)) == repo.audioUnavailable())
        #expect(await repo.pending(account: "a") == nil)
    }
    @Test func availableEngineInvitesWithConversationAndAnswersTheSeenVersion() async {
        let fixture = ProxyTransport { request in
            switch request.method {
            case "call.invite":
                #expect(request.body == .object(["conversation_id": .string("thread")])); #expect(request.operationID != nil)
                return row(phase: "outgoing_ringing", seq: 1, direction: "outgoing")
            case "call.list": return .object(["calls": .array([row(seq: 4)])])
            case "call.answer":
                #expect(request.body == .object(["call_id": .string("c")])); #expect(request.operationID?.rawValue == "answer-key")
                return row(phase: "connecting", seq: 5)
            default: Issue.record("Unexpected operation \(request.method)"); return .null
            }
        }
        let repo = repository(fixture, engine: FakeCallMediaEngine())
        guard case .success(let outgoing) = await repo.start(account: "a", conversation: "thread") else { Issue.record("Invite failed"); return }
        #expect(outgoing.phase == .outgoingRinging); #expect(outgoing.direction == .outgoing)
        #expect(await repo.start(account: "a", conversation: "") == .failure(.invalidInput))
        guard let incoming = await first(repo) else { Issue.record("No call"); return }
        guard case .success(let answered) = await repo.signal(account: "a", attempt: CallSignalAttempt(expected: incoming, signal: .answer, operationID: "answer-key")) else { Issue.record("Answer failed"); return }
        #expect(answered.phase == .connecting); #expect(await repo.pending(account: "a") == nil)
    }
    @Test func uncertainInviteIsNotRetriedAsANewInvite() async {
        let fixture = ProxyTransport { _ in .object([:]) }
        let repo = repository(fixture, engine: FakeCallMediaEngine())
        #expect(await repo.start(account: "a", conversation: "thread") == .failure(.outcomeUnknown))
        #expect(fixture.calls.withLock { $0.count == 1 })
    }
    @Test func liveStateSubscribesToTheSpecificCallTopic() async {
        let topics = Mutex<[String]>([])
        let fixture = ProxyTransport(onSubscribe: { filter in if case .array(let values)? = filter.body["topics"] { topics.withLock { $0 = values.compactMap(\.string) } }; throw BridgeError.invalidInput }) { _ in .null }
        let observation = await repository(fixture).observe(account: "a")
        for await _ in observation.stream { break }
        await observation.stop()
        #expect(topics.withLock { $0.contains("call.changed") && !$0.contains("*") })
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
        guard let selected = await first(repo) else { Issue.record("No call"); return }
        let attempt = CallSignalAttempt(expected: selected, signal: .hangup, operationID: "retained")
        #expect(await repo.signal(account: "a", attempt: attempt) == .failure(.outcomeUnknown)); #expect(await repo.pending(account: "a") == attempt)
        let terminalFixture = ProxyTransport { _ in .object(["calls": .array([row(phase: "ended")])]) }
        let terminal = repository(terminalFixture)
        guard case .success(let ended) = await terminal.signal(account: "a", attempt: attempt) else { Issue.record("Terminal state not reconciled"); return }
        #expect(ended.phase == .ended); #expect(terminalFixture.calls.withLock { $0.count == 1 && $0.first?.method == "call.list" })
    }
}
