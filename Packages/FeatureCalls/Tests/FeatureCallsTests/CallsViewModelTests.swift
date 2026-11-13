// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureCalls
private actor CallsFake: CallsRepository {
    let journal = RetainedMutation<CallSignalArguments, CallRecord>()
    let gate: MutationGate?
    var rows = [CallRecord(id: "c", conversationID: "thread", peerID: "peer", direction: .incoming, phase: .incomingRinging, sequence: 7, createdAt: 1_800_000_000)]
    private(set) var attempts: [CallSignalAttempt] = []
    init(gate: MutationGate? = nil) { self.gate = gate }
    func list(account: String) -> RepositoryResult<[CallRecord]> { .success(rows) }
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
        let ended = CallRecord(id: attempt.expected.id, conversationID: "thread", peerID: "peer", direction: .incoming, phase: .ended, endReason: "declined", sequence: 8, createdAt: 1_800_000_000, endedAt: 1_800_000_010)
        rows = [ended]; return .success(ended)
    }
    func start(account: String, conversation: String) -> RepositoryResult<CallRecord> { .failure(audioUnavailable()) }
    func answer(account: String, expected: CallRecord) -> RepositoryResult<CallRecord> { .failure(audioUnavailable()) }
    nonisolated func audioUnavailable() -> AppFailure { .unsupported }
    func observe(account: String) -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
}
private struct MicrophoneFake: MicrophoneRepository { func status() async -> MicrophoneStatus { .denied } }
@Suite(.timeLimit(.minutes(1))) @MainActor struct CallsViewModelTests {
    @Test func onlyFreshKnownCallAndVersionMayDeclineAndOnlyRealResultEndsIt() async {
        let fake = CallsFake(), model = CallsViewModel(repository: CallsFake(), microphone: MicrophoneFake(), account: "a", emit: { _ in })
        model.send(.refresh); await model.settle(); model.send(.mode(.detail("missing"))); #expect(model.state.mode == .history)
        model.send(.disappeared)
        let vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .detail("c")), emit: { _ in })
        vm.send(.refresh); await vm.settle(); #expect(vm.state.microphone == .denied); #expect(vm.state.canDecline)
        vm.send(.signal(.decline, callID: "missing", sequence: 7)); vm.send(.signal(.decline, callID: "c", sequence: 6)); await vm.settle(); #expect(await fake.attempts.isEmpty)
        vm.send(.signal(.decline, callID: "c", sequence: 7)); #expect(vm.state.selected?.phase == .incomingRinging)
        await vm.settle(); #expect(vm.state.selected?.phase == .ended); #expect(await fake.attempts.count == 1)
        vm.send(.filter("other")); #expect(vm.state.visibleCalls.isEmpty); vm.send(.disappeared); #expect(vm.state.calls.isEmpty)
    }
    @Test func unavailableStartAnswerAndAudioNeverInventCallsOrPermissionGrants() async {
        var events: [CallsEvent] = []
        let fake = CallsFake(), vm = CallsViewModel(repository: fake, microphone: MicrophoneFake(), account: "a", state: CallsState(mode: .dial("thread")), emit: { events.append($0) })
        vm.send(.start); await vm.settle(); #expect(vm.state.failure == .unsupported); #expect(vm.state.calls.isEmpty)
        vm.send(.refresh); await vm.settle(); vm.send(.mode(.detail("c"))); await vm.settle(); vm.send(.answer); await vm.settle()
        #expect(vm.state.failure == .unsupported); #expect(vm.state.selected?.phase == .incomingRinging)
        vm.send(.audioControl); vm.send(.openSettings); #expect(events == [.openSystemSettings]); #expect(await fake.attempts.isEmpty)
        #expect(vm.state.microphone == .denied); vm.send(.disappeared)
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
