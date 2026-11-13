// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import Testing
import AppData
@testable import FeatureTasks
private actor TerminalTasksRepository: TasksRepository {
    nonisolated let readEntered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    nonisolated let observed = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    nonisolated let initialProjection = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var reads = 0
    private var continuation: AsyncStream<RepositoryUpdate>.Continuation?
    private var pendingRead: CheckedContinuation<Void, Never>?
    private var blocking = false
    private let row = TaskRecord(id: "t", conversationID: "thread", version: 7, title: "Confirmed", status: "proposed", requester: nil, assignee: "agent")
    func blockNextRead() { blocking = true }
    func deliverInitialInvalidation() { continuation?.yield(.invalidated) }
    func releaseRead() { pendingRead?.resume(); pendingRead = nil }
    func end(_ failure: AppFailure?) { if let failure { continuation?.yield(.failed(failure)) }; continuation?.finish() }
    func page(account: String, conversation: String, cursor: String?) -> RepositoryResult<TaskPage> { .success(TaskPage(rows: [row])) }
    func detail(account: String, conversation: String, task: String) async -> RepositoryResult<TaskRecord> {
        reads += 1
        // The initial observation invalidation must cause its follow-up read before the
        // test introduces the deliberately stale read. Stream creation alone is not delivery.
        if reads == 2 { initialProjection.continuation.yield(()) }
        if blocking {
            blocking = false
            await withCheckedContinuation { waiter in pendingRead = waiter; readEntered.continuation.yield(()) }
            // Deliberately ignores cancellation, like a completion already queued by the SDK.
            return .success(TaskRecord(id: "t", conversationID: "thread", version: 6, title: "Old read", status: "proposed", requester: nil, assignee: "agent"))
        }
        return .success(row)
    }
    func permissions(account: String) -> RepositoryResult<[PermissionRecord]> { .success([]) }
    func pending(account: String) -> PendingTaskMutation? { nil }
    func mutate(account: String, attempt: PendingTaskMutation) -> RepositoryResult<TaskMutationOutcome> { .failure(.unsupported) }
    nonisolated func unavailable() -> AppFailure { .unsupported }
    func observe(account: String) -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); continuation = pair.continuation
        // Control delivery independently of subscription creation to reproduce the CI ordering.
        observed.continuation.yield(())
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct TasksTerminalObservationTests {
    @Test func terminalFailureOrCleanFinishFencesAnOlderReadEvenIfItCompletesSuccessfully() async {
        for failure: AppFailure? in [.locked, .offline, .resyncRequired, nil] {
            let repository = TerminalTasksRepository()
            let vm = TasksViewModel(repository: repository, conversations: UnavailableConversationsRepository(), account: "a", state: TasksState(mode: .detail(conversation: "thread", task: "t")), emit: { _ in })
            let changed = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await repository.releaseRead(); await repository.end(.failed)
                repository.observed.continuation.finish(); repository.readEntered.continuation.finish()
                repository.initialProjection.continuation.finish(); changed.continuation.finish()
            }
            vm.send(.appeared)
            var observed = repository.observed.stream.makeAsyncIterator(); #expect(await observed.next() != nil)
            await vm.settle()
            // Reproduce the problematic order: the first read succeeds before the initial
            // invalidation arrives. Finish its projection before introducing the stale read.
            await repository.deliverInitialInvalidation()
            var projected = repository.initialProjection.stream.makeAsyncIterator(); #expect(await projected.next() != nil)
            await vm.settle()
            #expect(vm.state.fresh); vm.send(.prepare(.accept)); #expect(vm.state.confirmation != nil)
            await repository.blockNextRead(); vm.send(.refresh)
            var entered = repository.readEntered.stream.makeAsyncIterator(); #expect(await entered.next() != nil)
            withObservationTracking { _ = vm.state.failure } onChange: { changed.continuation.yield(()) }
            await repository.end(failure); var transition = changed.stream.makeAsyncIterator(); #expect(await transition.next() != nil)
            #expect(!vm.state.fresh); #expect(!vm.state.loading); #expect(vm.state.confirmation == nil)
            if failure == .locked { #expect(vm.state.selected == nil); #expect(vm.state.rows.isEmpty); #expect(vm.state.permissions.isEmpty) }
            await repository.releaseRead(); await vm.settle()
            #expect(!vm.state.fresh); #expect(vm.state.failure == (failure ?? .resyncRequired)); #expect(vm.state.selected?.title != "Old read")
            vm.send(.prepare(.accept)); #expect(vm.state.confirmation == nil)
            changed.continuation.finish(); deadline.cancel(); await deadline.value; vm.send(.disappeared)
            repository.observed.continuation.finish(); repository.readEntered.continuation.finish(); repository.initialProjection.continuation.finish()
        }
    }
}
