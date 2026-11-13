// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import Testing
import AppData
@testable import FeatureGroups
private actor GroupsFake: GroupsRepository {
    let journal = RetainedMutation<GroupMutation, GroupMutationOutcome>()
    let gate: MutationGate?
    private var updates: AsyncStream<RepositoryUpdate>.Continuation?
    private(set) var attempts: [PendingGroupMutation] = []
    var admin = true
    var createPending = false
    var readFailure: AppFailure?
    func setReadFailure(_ value: AppFailure?) { readFailure = value }
    func setCreatePending() { createPending = true }
    init(gate: MutationGate? = nil) { self.gate = gate }
    func setAdmin(_ value: Bool) { admin = value; updates?.yield(.invalidated) }
    func list(account: String) -> RepositoryResult<[GroupRecord]> { .success([GroupRecord(id: "g", name: "Research", epoch: 9, members: ["phone","peer-phone"])]) }
    func conversation(account: String, group: String) -> RepositoryResult<String> { .success("canonical-thread") }
    func detail(account: String, group: String) -> RepositoryResult<GroupDetail> {
        if let readFailure { return .failure(readFailure) }
        return .success(GroupDetail(group: GroupRecord(id: "g", name: "Research", epoch: 9, members: ["phone","peer-phone"]), roster: [GroupMemberRecord(principal: "owner", root: "root-own", device: "phone", role: admin ? "owner" : "member"), GroupMemberRecord(principal: "peer", root: "root-peer", device: "peer-phone", role: "member")], ownRoot: "root-own", ownDevice: "phone", authorized: true))
    }
    func invitations(account: String) -> RepositoryResult<[GroupInvitation]> { .success([]) }
    func requests(account: String, group: String) -> RepositoryResult<[GroupRequestRecord]> { .success([]) }
    func pending(account: String) async -> PendingGroupMutation? {
        guard let entry = await journal.snapshot(scope: account), entry.unresolved else { return nil }
        return PendingGroupMutation(mutation: entry.arguments, operationID: entry.operationID)
    }
    func mutate(account: String, mutation: GroupMutation, operationID: String) async -> RepositoryResult<GroupMutationOutcome> {
        await journal.run(scope: account, arguments: mutation, operationID: operationID) { await self.perform(mutation, operationID) }
    }
    func perform(_ mutation: GroupMutation, _ operationID: String) async -> RepositoryResult<GroupMutationOutcome> {
        attempts.append(PendingGroupMutation(mutation: mutation, operationID: operationID))
        if let gate { await gate.wait(); return .failure(.outcomeUnknown) }
        if case .create = mutation { return .success(GroupMutationOutcome(groupID: "g", waitingForOwner: createPending)) }
        return .success(GroupMutationOutcome(groupID: mutation.groupID, waitingForOwner: true, requestID: "request"))
    }
    func observe(account: String) -> RepositoryObservation { let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); updates = pair.continuation; pair.continuation.yield(.invalidated); return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() }) }
    nonisolated func unavailable(_ capability: GroupUnavailable) -> AppFailure { .unsupported }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct GroupsViewModelTests {
    @Test func authoritativeCreationResolvesCanonicalConversationOnceAndFailuresDoNotNavigate() async {
        for kind in 0..<3 {
            let fake = GroupsFake(); var events: [GroupsEvent] = []
            if kind == 1 { await fake.setReadFailure(.offline) }
            if kind == 2 { await fake.setCreatePending() }
            let vm = GroupsViewModel(repository: fake, contacts: UnavailableContactsRepository(), account: "a", state: GroupsState(mode: .create), emit: { events.append($0) })
            vm.send(.name("Research")); vm.send(.prepareCreate)
            guard let confirmation = vm.state.confirmation else { Issue.record("No creation selected"); return }
            vm.send(.confirm(confirmation.id)); await vm.settle()
            let destinations = events.compactMap { event -> AppRoute? in if case .navigate(let route) = event { route } else { nil } }
            #expect(destinations == (kind == 0 ? [.groupConversation("canonical-thread", title: "Research")] : []))
            if kind == 1 { #expect(vm.state.failure == .offline) }
            if kind == 2 { #expect(vm.state.outcome?.waitingForOwner == true) }
            vm.send(.disappeared)
        }
    }
    @Test func groupNavigationUsesRepositoryCanonicalConversationAndKnownGroupOnly() async {
        var events: [GroupsEvent] = []
        let vm = GroupsViewModel(repository: GroupsFake(), contacts: UnavailableContactsRepository(), account: "a", emit: { events.append($0) })
        vm.send(.refresh); await vm.settle(); vm.send(.openMessages("unknown")); await vm.settle(); #expect(events.isEmpty)
        vm.send(.openMessages("g")); await vm.settle(); #expect(events == [.navigate(.groupConversation("canonical-thread", title: "Research"))]); vm.send(.disappeared)
    }
    @Test func exactConfirmationPrecedesRoleMutationAndPendingDoesNotInventAppliedRole() async {
        let fake = GroupsFake(), state = GroupsState(mode: .members("g"))
        let vm = GroupsViewModel(repository: fake, contacts: UnavailableContactsRepository(), account: "a", state: state, emit: { _ in })
        vm.send(.refresh); await vm.settle()
        let peer = "root-peer\u{0}peer-phone"
        vm.send(.prepareRole(peer, "admin")); #expect(await fake.attempts.isEmpty)
        guard let selected = vm.state.confirmation else { Issue.record("Known role target was not selected"); return }
        vm.send(.confirm(UUID())); await vm.settle(); #expect(await fake.attempts.isEmpty)
        vm.send(.confirm(selected.id)); await vm.settle()
        #expect(await fake.attempts.count == 1); #expect(vm.state.outcome?.waitingForOwner == true)
        #expect(vm.state.detail?.roster.first(where: { $0.root == "root-peer" })?.role == "member")
        vm.send(.filter("missing")); #expect(vm.state.visibleGroups.isEmpty)
        vm.send(.filter("Research")); #expect(vm.state.visibleGroups.map(\.id) == ["g"])
        vm.send(.mode(.detail("unknown"))); #expect(vm.state.mode == .members("g")); vm.send(.disappeared)
    }
    @Test func cancelledWaiterAndCoordinatorReplacementKeepOriginalMutationIdentity() async {
        let gate = MutationGate(), fake = GroupsFake(gate: gate)
        defer { gate.release() }
        let vm = GroupsViewModel(repository: fake, contacts: UnavailableContactsRepository(), account: "a", state: GroupsState(mode: .create), emit: { _ in })
        vm.send(.name("Group")); vm.send(.prepareCreate)
        guard let confirmation = vm.state.confirmation else { Issue.record("Create not selected"); return }
        vm.send(.confirm(confirmation.id)); var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next()
        vm.send(.disappeared); gate.release(); await vm.settle()
        let replacement = GroupsCoordinator(repository: fake, contacts: UnavailableContactsRepository(), account: "a")
        replacement.send(.refresh); await replacement.viewModel.settle()
        #expect(replacement.viewModel.state.pending == confirmation.attempt)
        replacement.send(.name("Different")); replacement.send(.prepareCreate); #expect(replacement.viewModel.state.confirmation == nil)
        replacement.send(.reconcileOriginal("wrong")); await replacement.viewModel.settle(); #expect(await fake.attempts.count == 1)
        replacement.send(.reconcileOriginal(confirmation.attempt.operationID)); await replacement.viewModel.settle()
        #expect(await fake.attempts.count == 2); #expect((await fake.attempts).allSatisfy { $0 == confirmation.attempt })
        replacement.send(.disappeared)
    }
    @Test func liveAuthorityChangeRevokesPendingHostConfirmation() async {
        let fake = GroupsFake()
        let model = GroupsViewModel(repository: fake, contacts: UnavailableContactsRepository(), account: "a", state: GroupsState(mode: .members("g")), emit: { _ in })
        model.send(.refresh); await model.settle(); model.send(.prepareRemove("root-peer\u{0}peer-phone"))
        guard let confirmation = model.state.confirmation else { Issue.record("Known removal not selected"); return }
        let events = AsyncStream<Void>.makeStream(); let deadline = Task { try? await Task.sleep(for: .seconds(5)); events.continuation.finish() }
        withObservationTracking { _ = model.state.confirmation } onChange: { events.continuation.yield(()) }
        await fake.setAdmin(false); var iterator = events.stream.makeAsyncIterator(); #expect(await iterator.next() != nil); deadline.cancel(); events.continuation.finish()
        await model.settle(); #expect(model.state.confirmation == nil); #expect(!model.state.canManage)
        model.send(.confirm(confirmation.id)); await model.settle(); #expect(await fake.attempts.isEmpty)
        model.send(.prepareRemove("root-peer\u{0}peer-phone")); #expect(model.state.mode == .managementUnavailable); model.send(.disappeared)
    }
    @Test func unavailableRepositoryNeverCreatesProjectedGroupsOrFakeAcknowledgement() async {
        let model = GroupsViewModel(repository: UnavailableGroupsRepository(), contacts: UnavailableContactsRepository(), account: "a", emit: { _ in })
        model.send(.refresh); await model.settle()
        #expect(model.state.groups.isEmpty); #expect(model.state.failure == .sdkUnavailable); #expect(model.state.outcome == nil)
        model.send(.disappeared)
    }
}
