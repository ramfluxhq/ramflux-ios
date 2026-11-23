// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureCalls

private let everything = CallMediaAvailability.available(CallMediaCapabilities(audio: true, video: true, cameraSwitch: true, speakerRoute: true))

actor CallsFake: CallsRepository {
    let journal = RetainedMutation<CallSignalArguments, CallRecord>()
    let gate: MutationGate?
    nonisolated let media: CallMediaAvailability
    nonisolated let events = AsyncStream<CallMediaEvent>.makeStream()
    var rows = [CallRecord(id: "c", conversationID: "thread", peerID: "peer", direction: .incoming, phase: .incomingRinging, sequence: 7, createdAt: 1_800_000_000)]
    private(set) var attempts: [CallSignalAttempt] = []
    private(set) var invites: [String] = []
    private(set) var connected: [String] = []
    private(set) var controls: [CallMediaControl] = []
    init(gate: MutationGate? = nil, media: CallMediaAvailability = RefusingCallMediaEngine().availability()) { self.gate = gate; self.media = media }
    func set(_ rows: [CallRecord]) { self.rows = rows }
    nonisolated func mediaAvailability() -> CallMediaAvailability { media }
    func history(account: String, cursor: String?) -> RepositoryResult<CallHistoryPage> { .success(CallHistoryPage(rows: rows, nextCursor: nil)) }
    func pending(account: String) async -> CallSignalAttempt? {
        guard let snapshot = await journal.snapshot(scope: account), snapshot.unresolved else { return nil }
        return CallSignalAttempt(expected: snapshot.arguments.expected, signal: snapshot.arguments.signal, operationID: snapshot.operationID)
    }
    func signal(account: String, attempt: CallSignalAttempt) async -> RepositoryResult<CallRecord> {
        await journal.run(scope: account, arguments: CallSignalArguments(expected: attempt.expected, signal: attempt.signal), operationID: attempt.operationID) { await self.perform(attempt) }
    }
    private func perform(_ attempt: CallSignalAttempt) async -> RepositoryResult<CallRecord> {
        attempts.append(attempt)
        if let gate { await gate.wait(); return .failure(.outcomeUnknown) }
        let next = attempt.signal == .answer
            ? CallRecord(id: attempt.expected.id, conversationID: "thread", peerID: "peer", direction: .incoming, phase: .active, sequence: 8, createdAt: 1_800_000_000, answeredAt: 1_800_000_005)
            : CallRecord(id: attempt.expected.id, conversationID: "thread", peerID: "peer", direction: .incoming, phase: .ended, endReason: "declined", sequence: 8, createdAt: 1_800_000_000, endedAt: 1_800_000_010)
        rows = [next]; return .success(next)
    }
    func start(account: String, conversation: String) -> RepositoryResult<CallRecord> {
        guard media.capabilities != nil else { return .failure(audioUnavailable()) }
        invites.append(conversation)
        let row = CallRecord(id: "out", conversationID: conversation, peerID: "peer", direction: .outgoing, phase: .outgoingRinging, sequence: 1, createdAt: 1_800_000_000)
        rows = [row]; return .success(row)
    }
    func connectMedia(account: String, call: CallRecord) -> RepositoryResult<Void> { connected.append(call.id); return .success(()) }
    func control(_ control: CallMediaControl, callID: String) -> RepositoryResult<Void> { controls.append(control); return .success(()) }
    nonisolated func mediaEvents() -> AsyncStream<CallMediaEvent> { events.stream }
    func observe(account: String) -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
}
private struct MicrophoneFake: MicrophoneRepository { var value: MicrophoneStatus = .denied; func status() async -> MicrophoneStatus { value } }
@MainActor final class PermissionFake: CallPermissionRequesting {
    var grant: Bool
    private(set) var asked: [DevicePermission] = []
    init(grant: Bool) { self.grant = grant }
    func requestPermission(_ permission: DevicePermission, resolved: @escaping @MainActor (Bool) -> Void) { asked.append(permission); resolved(grant) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct CallsViewModelTests {
    @Test func onlyFreshKnownCallAndVersionMayDeclineAndOnlyRealResultEndsIt() async {
        let fake = CallsFake(), model = CallsViewModel(repository: CallsFake(), microphone: MicrophoneFake(), account: "a", emit: { _ in })
        model.send(.refresh); await model.settle(); model.send(.mode(.detail("missing"))); #expect(model.state.mode == .history)
        model.send(.disappeared)
        let vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .detail("c")), emit: { _ in })
        vm.send(.refresh); await vm.settle(); #expect(vm.state.microphone == .denied); #expect(vm.state.canDecline); #expect(vm.state.stage == .incoming)
        vm.send(.signal(.decline, callID: "missing", sequence: 7)); vm.send(.signal(.decline, callID: "c", sequence: 6)); await vm.settle(); #expect(await fake.attempts.isEmpty)
        vm.send(.signal(.decline, callID: "c", sequence: 7)); #expect(vm.state.selected?.phase == .incomingRinging)
        await vm.settle(); #expect(vm.state.selected?.phase == .ended); #expect(await fake.attempts.count == 1)
        vm.send(.filter("other")); #expect(vm.state.visibleCalls.isEmpty); vm.send(.disappeared); #expect(vm.state.calls.isEmpty)
    }
    @Test func refusingEngineNeverInvitesAnswersOrAsksForPermissions() async {
        var events: [CallsEvent] = []
        let fake = CallsFake(), permissions = PermissionFake(grant: true)
        let vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .dial("thread")), permissions: permissions, emit: { events.append($0) })
        #expect(!vm.state.canCall)
        vm.send(.start); await vm.settle(); #expect(vm.state.failure == fake.audioUnavailable()); #expect(vm.state.calls.isEmpty)
        vm.send(.refresh); await vm.settle(); vm.send(.mode(.detail("c"))); await vm.settle()
        #expect(vm.state.canDecline); #expect(!vm.state.canAnswer)
        vm.send(.answer); await vm.settle()
        #expect(vm.state.failure == fake.audioUnavailable()); #expect(vm.state.selected?.phase == .incomingRinging)
        vm.send(.control(.mute(true))); vm.send(.openSettings); #expect(events == [.openSystemSettings])
        #expect(await fake.attempts.isEmpty); #expect(await fake.invites.isEmpty); #expect(await fake.controls.isEmpty); #expect(permissions.asked.isEmpty)
        vm.send(.disappeared)
    }
    @Test func availableEngineAsksForTheMicrophoneBeforeInviting() async {
        let fake = CallsFake(media: everything), permissions = PermissionFake(grant: false)
        var events: [CallsEvent] = []
        let vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .dial("thread")), permissions: permissions, emit: { events.append($0) })
        vm.send(.start); await vm.settle()
        #expect(permissions.asked == [.microphone]); #expect(vm.state.permissionNeeded == .microphone); #expect(await fake.invites.isEmpty); #expect(events.isEmpty)
        vm.send(.dismissPermission); #expect(vm.state.permissionNeeded == nil)
        permissions.grant = true; vm.send(.start); await vm.settle()
        #expect(await fake.invites == ["thread"]); #expect(vm.state.mode == .detail("out")); #expect(vm.state.stage == .outgoing)
        #expect(events.map { if case .outgoingStarted(let row) = $0 { row.id } else { "" } } == ["out"])
        vm.send(.disappeared)
    }
    @Test func answerConnectsMediaOnceAndFollowsEngineState() async {
        let fake = CallsFake(media: everything), permissions = PermissionFake(grant: true)
        let vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .detail("c")), permissions: permissions, emit: { _ in })
        vm.send(.refresh); await vm.settle(); #expect(vm.state.canAnswer)
        vm.send(.answer); await vm.settle()
        #expect((await fake.attempts).map(\.signal) == [.answer]); #expect(vm.state.selected?.phase == .active); #expect(vm.state.stage == .inCall)
        vm.send(.refresh); await vm.settle()
        #expect(await fake.connected == ["c"])
        fake.events.continuation.yield(.state(callID: "c", .reconnecting))
        for _ in 0..<50 where vm.state.stage != .connectionLost { await Task.yield() }
        #expect(vm.state.stage == .connectionLost)
        vm.send(.control(.mute(true))); vm.send(.control(.route(.speaker)))
        for _ in 0..<50 where !(vm.state.muted && vm.state.route == .speaker) { await Task.yield() }
        #expect(await fake.controls == [.mute(true), .route(.speaker)]); #expect(vm.state.muted); #expect(vm.state.route == .speaker)
        vm.send(.disappeared)
    }
    @Test func controlsAreGovernedByEngineCapabilities() async {
        let voiceOnly = CallMediaCapabilities(audio: true)
        #expect(CallsViewModel.allowed(.mute(true), voiceOnly)); #expect(!CallsViewModel.allowed(.route(.speaker), voiceOnly))
        #expect(!CallsViewModel.allowed(.camera(true), voiceOnly)); #expect(!CallsViewModel.allowed(.switchCamera, voiceOnly))
        let fake = CallsFake(media: .available(voiceOnly))
        await fake.set([CallRecord(id: "c", conversationID: "thread", peerID: "peer", direction: .outgoing, phase: .active, sequence: 3, createdAt: 1_800_000_000)])
        let vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .detail("c")), emit: { _ in })
        vm.send(.refresh); await vm.settle(); vm.send(.control(.camera(true))); vm.send(.control(.switchCamera)); await vm.settle()
        #expect(await fake.controls.isEmpty); vm.send(.disappeared)
    }
    @Test func systemSettingsFailureIsTyped() {
        let vm = CallsViewModel(repository: CallsFake(), microphone: MicrophoneFake(), account: "a", emit: { _ in })
        vm.send(.settingsResult(false)); #expect(vm.state.failure == .localFailure)
    }
    @Test func cancellationAndReplacementKeepOriginalSignalingKey() async {
        let gate = MutationGate(), fake = CallsFake(gate: gate); defer { gate.release() }
        let vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .detail("c")), emit: { _ in })
        vm.send(.refresh); await vm.settle(); vm.send(.signal(.hangup, callID: "c", sequence: 7))
        var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next()
        vm.send(.disappeared); gate.release(); await vm.settle()
        let replacement = CallsCoordinator(repository: fake, microphone: MicrophoneFake(), account: "a")
        replacement.send(.refresh); await replacement.viewModel.settle()
        guard let pending = replacement.viewModel.state.pending else { Issue.record("Lost pending action"); return }
        replacement.send(.reconcile("wrong")); await replacement.viewModel.settle(); #expect(await fake.attempts.count == 1)
        replacement.send(.reconcile(pending.operationID)); await replacement.viewModel.settle()
        #expect(await fake.attempts.count == 2); #expect((await fake.attempts).allSatisfy { $0 == pending }); replacement.send(.disappeared)
    }
}
