// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import Testing
import AppData
@testable import FeatureTasks
private actor TasksFake: TasksRepository {
    let journal = RetainedMutation<TaskMutationArguments, TaskMutationOutcome>()
    let gate: MutationGate?
    let task = TaskRecord(id: "t", conversationID: "thread", version: 7, title: "Review", status: "proposed", requester: nil, assignee: "agent")
    private var continuation: AsyncStream<RepositoryUpdate>.Continuation?
    private(set) var attempts: [PendingTaskMutation] = []
    init(gate: MutationGate? = nil) { self.gate = gate }
    func page(account: String, conversation: String, cursor: String?) -> RepositoryResult<TaskPage> { .success(TaskPage(rows: [task], nextCursor: cursor == nil ? "next" : nil)) }
    func detail(account: String, conversation: String, task: String) -> RepositoryResult<TaskRecord> { .success(self.task) }
    let approval = PermissionApproval(referenceID: "ap", server: "svc", tool: "send", capability: "email_send", status: "pending", expiresAt: 4_102_444_800, confirmationMode: "local")
    private(set) var decisions: [(String, Bool)] = []
    func permissions(account: String) -> RepositoryResult<[PermissionRecord]> { .success([.approval(approval)]) }
    func permissionsPage(account: String, cursor: String?, limit: Int) -> RepositoryResult<RowPage<PermissionRecord>> { .success(RowPage(rows: [.approval(approval)], nextCursor: nil)) }
    func decideApproval(account: String, approval: PermissionApproval, approve: Bool, operationID: String) -> RepositoryResult<Void> { decisions.append((approval.referenceID, approve)); return .success(()) }
    var decisionCount: Int { decisions.count }
    var lastDecision: Bool? { decisions.last?.1 }
    func pending(account: String) async -> PendingTaskMutation? { guard let entry = await journal.snapshot(scope: account), entry.unresolved else { return nil }; return PendingTaskMutation(arguments: entry.arguments, operationID: entry.operationID) }
    func mutate(account: String, attempt: PendingTaskMutation) async -> RepositoryResult<TaskMutationOutcome> { await journal.run(scope: account, arguments: attempt.arguments, operationID: attempt.operationID) { await self.perform(attempt) } }
    private func perform(_ attempt: PendingTaskMutation) async -> RepositoryResult<TaskMutationOutcome> { attempts.append(attempt); if let gate { await gate.wait(); return .failure(.outcomeUnknown) }; return .success(TaskMutationOutcome(taskID: "t", pending: true)) }
    nonisolated func unavailable() -> AppFailure { .unsupported }
    func invalidate() { continuation?.yield(.invalidated) }
    func observe(account: String) -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); continuation = pair.continuation; pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct TasksViewModelTests {
    @Test func knownContextPaginationAndExactHostConfirmationPrecedeMutation() async {
        let fake = TasksFake(), vm = TasksViewModel(repository: TasksFake(), conversations: UnavailableConversationsRepository(), account: "a", emit: { _ in })
        vm.send(.mode(.list("unknown"))); #expect(vm.state.mode == .conversations); vm.send(.disappeared)
        let model = TasksViewModel(repository: fake, conversations: UnavailableConversationsRepository(), account: "a", state: TasksState(mode: .list("thread")), emit: { _ in })
        model.send(.refresh); await model.settle(); #expect(model.state.tasks.count == 1); #expect(model.state.tasks.canLoadAfter); model.send(.loadMore); await model.settle(); #expect(model.state.tasks.count == 1); #expect(!model.state.tasks.canLoadAfter)
        model.send(.mode(.detail(conversation: "thread", task: "t"))); await model.settle(); model.send(.prepare(.accept))
        guard let confirmation = model.state.confirmation else { Issue.record("No confirmation"); return }
        model.send(.confirm(UUID())); await model.settle(); #expect(await fake.attempts.isEmpty)
        model.send(.confirm(confirmation.id)); await model.settle(); #expect(await fake.attempts.count == 1); #expect(model.state.outcome?.pending == true); #expect(model.state.selected?.status == "proposed"); model.send(.disappeared)
    }
    @Test func approvalDecisionNeedsTheHostConfirmationOfTheSameApproval() async {
        let fake = TasksFake()
        let vm = TasksViewModel(repository: fake, conversations: UnavailableConversationsRepository(), account: "a", state: TasksState(mode: .permissions), emit: { _ in })
        vm.send(.refresh); await vm.settle()
        vm.send(.mode(.permission("approval:ap"))); await vm.settle()
        vm.send(.prepareApproval(approve: false))
        guard let confirmation = vm.state.approvalConfirmation else { Issue.record("no confirmation"); return }
        #expect(!confirmation.approve)
        vm.send(.confirmApproval(UUID())); await vm.settle(); #expect(await fake.decisionCount == 0)
        vm.send(.confirmApproval(confirmation.id)); await vm.settle()
        #expect(await fake.decisionCount == 1); #expect(await fake.lastDecision == false); #expect(vm.state.approvalConfirmation == nil)
        vm.send(.disappeared)
    }
    @Test func appSignedApprovalsCannotBeApprovedButCanBeDenied() async {
        let vm = TasksViewModel(repository: TasksFake(), conversations: UnavailableConversationsRepository(), account: "a", emit: { _ in })
        var state = TasksState(mode: .permission("approval:remote"))
        let remote = PermissionApproval(referenceID: "remote", server: "svc", tool: "send", capability: "email_send", status: "pending", expiresAt: 4_102_444_800, confirmationMode: "remote_app")
        state.selectedPermission = .approval(remote); state.fresh = true
        let model = TasksViewModel(repository: TasksFake(), conversations: UnavailableConversationsRepository(), account: "a", state: state, emit: { _ in })
        model.send(.prepareApproval(approve: true)); #expect(model.state.approvalConfirmation == nil); #expect(model.state.failure == .unavailableResource("tasks.approval.appSignature"))
        model.send(.prepareApproval(approve: false)); #expect(model.state.approvalConfirmation?.approve == false)
        vm.send(.disappeared); model.send(.disappeared)
    }
    @Test func taskWindowStaysBoundedOverFiftyThousandRows() async {
        let rows = (0..<50_000).map { TaskRecord(id: "t\($0)", conversationID: "thread", version: 1, title: "Task \($0)", status: "running", requester: nil, assignee: "agent") }
        let pager = SnapshotPager<TaskRecord>()
        let read: RowPageReader<TaskRecord> = { cursor, limit in await pager.page(cursor: cursor, limit: limit, read: { .success(rows) }) }
        let clock = ContinuousClock(), start = clock.now
        guard case .success(var window) = await RowWindow<TaskRecord>.first(read) else { Issue.record("first failed"); return }
        for _ in 0..<40 { if case .success(let next) = await window.after(read) { window = next } }
        #expect(window.count <= RowWindow<TaskRecord>.defaultMaxRows); #expect(window.canLoadAfter)
        print("TASK_WINDOW_50K rows=\(window.count) pages=41 elapsed=\(clock.now - start)")
    }
    @Test func observationInvalidationRevokesHeldFacts() async {
        let fake = TasksFake(), vm = TasksViewModel(repository: TasksFake(), conversations: UnavailableConversationsRepository(), account: "a", emit: { _ in }); vm.send(.disappeared)
        let model = TasksViewModel(repository: fake, conversations: UnavailableConversationsRepository(), account: "a", state: TasksState(mode: .detail(conversation: "thread", task: "t")), emit: { _ in })
        model.send(.refresh); await model.settle(); model.send(.prepare(.cancel))
        guard let selected = model.state.confirmation else { Issue.record("No selection"); return }
        let pair = AsyncStream<Void>.makeStream(); let deadline = Task { try? await Task.sleep(for: .seconds(5)); pair.continuation.finish() }
        withObservationTracking { _ = model.state.confirmation } onChange: { pair.continuation.yield(()) }
        await fake.invalidate(); var iterator = pair.stream.makeAsyncIterator(); #expect(await iterator.next() != nil); deadline.cancel(); pair.continuation.finish()
        await model.settle(); #expect(model.state.confirmation == nil); model.send(.confirm(selected.id)); #expect(await fake.attempts.isEmpty); model.send(.disappeared)
    }
    @Test func concealedWaiterCannotLoseOriginalTaskAttempt() async {
        let gate = MutationGate(), fake = TasksFake(gate: gate); defer { gate.release() }
        let vm = TasksViewModel(repository: fake, conversations: UnavailableConversationsRepository(), account: "a", state: TasksState(mode: .detail(conversation: "thread", task: "t")), emit: { _ in })
        vm.send(.refresh); await vm.settle(); vm.send(.prepare(.accept)); guard let confirmation = vm.state.confirmation else { Issue.record("No selection"); return }
        vm.send(.confirm(confirmation.id)); var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next(); vm.send(.disappeared); gate.release(); await vm.settle()
        let replacement = TasksCoordinator(repository: fake, conversations: UnavailableConversationsRepository(), account: "a", mode: .permissions)
        replacement.send(.refresh); await replacement.viewModel.settle(); #expect(replacement.viewModel.state.pending == confirmation.attempt)
        replacement.send(.reconcile("wrong")); await replacement.viewModel.settle(); #expect(await fake.attempts.count == 1)
        replacement.send(.reconcile(confirmation.attempt.operationID)); await replacement.viewModel.settle(); #expect((await fake.attempts).count == 2); #expect((await fake.attempts).allSatisfy { $0 == confirmation.attempt }); replacement.send(.disappeared)
    }
}
