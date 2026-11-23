// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureCalls

@MainActor private final class ProviderFake: CallSystemProvider {
    var onAction: ((CallSystemAction) -> Bool)?
    var accept = true
    private(set) var log: [String] = []
    func reportIncoming(_ call: CallSystemCall) async -> Bool { log.append("incoming:" + call.callID); return accept }
    func startOutgoing(_ call: CallSystemCall) async -> Bool { log.append("start:" + call.callID); return true }
    func reportConnecting(_ uuid: UUID) { log.append("connecting") }
    func reportConnected(_ uuid: UUID) { log.append("connected") }
    func reportEnded(_ uuid: UUID, reason: CallSystemEndReason) { log.append("ended:\(reason)") }
    func requestEnd(_ uuid: UUID) async -> Bool { true }
    func requestMute(_ uuid: UUID, muted: Bool) async -> Bool { true }
}

private func call(_ id: String, _ phase: CallPhase, _ direction: CallDirection = .incoming, reason: String? = nil, seq: UInt64 = 1) -> CallRecord {
    CallRecord(id: id, conversationID: "thread", peerID: "peer", direction: direction, phase: phase, endReason: reason, sequence: seq, createdAt: 1_800_000_000)
}
private let voice = CallMediaAvailability.available(CallMediaCapabilities(audio: true))

@Suite @MainActor struct CallSystemBridgeTests {
    @Test func mappingReportsOnlyRealTransitions() {
        #expect(CallSystemMapping.effects(previous: nil, row: call("c", .incomingRinging), endedHere: false) == [.reportIncoming])
        #expect(CallSystemMapping.effects(previous: .incomingRinging, row: call("c", .incomingRinging), endedHere: false).isEmpty)
        #expect(CallSystemMapping.effects(previous: .outgoingRinging, row: call("c", .connecting, .outgoing), endedHere: false) == [.reportConnecting])
        #expect(CallSystemMapping.effects(previous: .connecting, row: call("c", .active, .outgoing), endedHere: false) == [.reportConnected])
        #expect(CallSystemMapping.effects(previous: .connecting, row: call("c", .active), endedHere: false).isEmpty)
        #expect(CallSystemMapping.effects(previous: nil, row: call("c", .ended, reason: "missed"), endedHere: false).isEmpty)
        #expect(CallSystemMapping.effects(previous: .active, row: call("c", .ended, reason: "completed"), endedHere: true).isEmpty)
        #expect(CallSystemMapping.effects(previous: .incomingRinging, row: call("c", .ended, reason: "missed"), endedHere: false) == [.reportEnded(.unanswered)])
        #expect(CallSystemMapping.reason(call("c", .ended, reason: "answered_elsewhere")) == .answeredElsewhere)
        #expect(CallSystemMapping.reason(call("c", .ended, reason: "declined")) == .declinedElsewhere)
        #expect(CallSystemMapping.reason(call("c", .ended, .outgoing, reason: "declined")) == .remoteEnded)
        #expect(CallSystemMapping.reason(call("c", .ended, reason: "failed")) == .failed)
        #expect(CallSystemMapping.reason(call("c", .ended, reason: "future_reason")) == .failed)
    }
    @Test func bridgeIsInertWhileTheEngineRefuses() async {
        let provider = ProviderFake()
        let bridge = CallSystemBridge(provider: provider, availability: { RefusingCallMediaEngine().availability() }, display: { $0.peerID })
        #expect(await bridge.update([call("c", .incomingRinging)]).isEmpty); #expect(provider.log.isEmpty)
        #expect(provider.onAction?(.answer(UUID())) == false)
    }
    @Test func bridgeFollowsAnIncomingCallAndTurnsSystemActionsIntoIntents() async {
        let provider = ProviderFake()
        let bridge = CallSystemBridge(provider: provider, availability: { voice }, display: { $0.peerID })
        var intents: [CallSystemIntent] = []
        bridge.onIntent = { intents.append($0) }
        await bridge.update([call("c", .incomingRinging)])
        guard let uuid = bridge.uuid(for: "c") else { Issue.record("Not reported"); return }
        #expect(provider.onAction?(.answer(uuid)) == true)
        #expect(provider.onAction?(.hold(uuid, true)) == false)
        #expect(provider.onAction?(.mute(uuid, true)) == true)
        #expect(provider.onAction?(.audioActivated) == true)
        await bridge.update([call("c", .active, seq: 2)])
        #expect(provider.onAction?(.end(uuid)) == true)
        await bridge.update([call("c", .ended, reason: "completed", seq: 3)])
        #expect(provider.log == ["incoming:c"])
        #expect(intents == [.answer(callID: "c"), .mute(callID: "c", true), .audio(active: true), .end(callID: "c")])
        #expect(bridge.uuid(for: "c") == nil)
    }
    @Test func refusedIncomingReportEndsTheCallAndOutgoingIsTracked() async {
        let provider = ProviderFake(); provider.accept = false
        let bridge = CallSystemBridge(provider: provider, availability: { voice }, display: { $0.peerID })
        var intents: [CallSystemIntent] = []
        bridge.onIntent = { intents.append($0) }
        await bridge.update([call("c", .incomingRinging)])
        #expect(intents == [.end(callID: "c")])
        await bridge.outgoingStarted(call("o", .outgoingRinging, .outgoing))
        await bridge.update([call("o", .connecting, .outgoing, seq: 2)])
        await bridge.update([call("o", .active, .outgoing, seq: 3)])
        await bridge.update([call("o", .ended, .outgoing, reason: "declined", seq: 4)])
        #expect(provider.log == ["incoming:c", "start:o", "connecting", "connected", "ended:remoteEnded"])
    }
    @Test func audioRoutesAndInterruptionsMap() {
        #expect(CallAudioMapping.route(port: "Speaker") == .speaker)
        #expect(CallAudioMapping.route(port: "Receiver") == .receiver)
        #expect(CallAudioMapping.route(port: "BluetoothHFP") == .bluetooth)
        #expect(CallAudioMapping.route(port: "Headphones") == .wired)
        #expect(CallAudioMapping.interruption(type: 1, options: 0) == .interrupted)
        #expect(CallAudioMapping.interruption(type: 0, options: 1) == .interruptionEnded(resume: true))
        #expect(CallAudioMapping.interruption(type: 0, options: 0) == .interruptionEnded(resume: false))
        #expect(CallAudioMapping.interruption(type: 7, options: 0) == nil)
    }
}

/// Scale rule 10: a synthetic 50,000-row paged history source.
private actor LargeHistory: CallsRepository {
    let total: Int
    let page: Int
    private(set) var reads = 0
    init(total: Int, page: Int) { self.total = total; self.page = page }
    func history(account: String, cursor: String?) -> RepositoryResult<CallHistoryPage> {
        reads += 1
        let start = Int(cursor ?? "0") ?? 0, end = min(total, start + page)
        let rows = (start..<end).map { CallRecord(id: "call-\($0)", conversationID: "thread", peerID: "peer-\($0 % 997)", direction: $0.isMultiple(of: 2) ? .incoming : .outgoing, phase: .ended, endReason: "completed", sequence: UInt64($0), createdAt: 1_800_000_000 - Int64($0), answeredAt: 1_800_000_000 - Int64($0), endedAt: 1_800_000_060 - Int64($0)) }
        return .success(CallHistoryPage(rows: rows, nextCursor: end < total ? String(end) : nil))
    }
    func pending(account: String) async -> CallSignalAttempt? { nil }
    func signal(account: String, attempt: CallSignalAttempt) async -> RepositoryResult<CallRecord> { .failure(.unsupported) }
    func start(account: String, conversation: String) async -> RepositoryResult<CallRecord> { .failure(.unsupported) }
    func observe(account: String) async -> RepositoryObservation { RepositoryObservation(stream: AsyncStream { $0.finish() }) }
}
private struct Granted: MicrophoneRepository { func status() async -> MicrophoneStatus { .granted } }

@Suite(.timeLimit(.minutes(1))) @MainActor struct CallHistoryScaleTests {
    @Test func fiftyThousandRowsStayInABoundedWindow() async {
        let source = LargeHistory(total: 50_000, page: 128)
        let vm = CallsViewModel(repository: source, microphone: Granted(), account: "a", emit: { _ in })
        let clock = ContinuousClock(), started = clock.now
        vm.send(.refresh); await vm.settle()
        var pages = 1
        while vm.state.nextCursor != nil { vm.send(.loadMore); await vm.settle(); pages += 1 }
        let loaded = clock.now - started
        let filterStart = clock.now; vm.send(.filter("peer-5")); let filtered = clock.now - filterStart
        #expect(vm.state.calls.count == CallsState.window); #expect(Set(vm.state.calls.map(\.id)).count == CallsState.window)
        #expect(!vm.state.visibleCalls.isEmpty)
        print("CALL_HISTORY_SCALE rows=50000 page=128 pagesRead=\(pages) window=\(vm.state.calls.count) load=\(loaded) filter=\(filtered) visible=\(vm.state.visibleCalls.count)")
        vm.send(.disappeared)
    }
}
