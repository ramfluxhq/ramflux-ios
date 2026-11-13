// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureContacts
private actor ContactsFake: ContactsRepository {
    let journal = RetainedMutation<ContactMutationArguments, Void>()
    let gate: MutationGate?
    private(set) var attempts: [(String, String)] = []
    init(gate: MutationGate? = nil) { self.gate = gate }
    func pendingMutation(account: String) async -> PendingContactMutation? {
        guard let row = await journal.snapshot(scope: account), row.unresolved else { return nil }
        return PendingContactMutation(arguments: row.arguments, operationID: row.operationID)
    }
    private(set) var decisions: [String] = []
    func contacts(account: String) -> RepositoryResult<[ContactRecord]> { .success([]) }
    func requests(account: String) -> RepositoryResult<[ContactRequestRecord]> { .success([
        ContactRequestRecord(id: "incoming", principal: "peer", name: "Peer", direction: "inbound", state: "pending"),
        ContactRequestRecord(id: "outgoing", principal: "peer", name: "Peer", direction: "outbound", state: "pending"),
    ]) }
    func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> {
        await journal.run(scope: account, arguments: .add(principal), operationID: operationID) { await self.perform(principal: principal, operationID: operationID) }
    }
    private func perform(principal: String, operationID: String) async -> RepositoryResult<Void> {
        attempts.append((operationID, principal)); if let gate { await gate.wait() }; return .failure(.outcomeUnknown)
    }
    func decide(account: String, request: String, decision: ContactDecision, operationID: String) -> RepositoryResult<Void> { decisions.append(request + ":" + decision.rawValue); return .success(()) }
    func safety(account: String, contact: ContactRecord) -> RepositoryResult<ContactSafety> { .failure(.unsupported) }
    func observe(account: String) -> RepositoryObservation { {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }() }
    nonisolated func unavailable(_ capability: ContactUnavailable) -> AppFailure { .unsupported }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct ContactsViewModelTests {
    @Test func accountFenceAndOriginalArgumentsSurviveCancelledWaiterAndCoordinatorReplacement() async {
        let gate = MutationGate(), fake = ContactsFake(gate: gate)
        defer { gate.release() }
        let first = ContactsCoordinator(repository: fake, account: "a", mode: .contacts, navigate: { _ in })
        first.send(.principal("peer")); first.send(.add)
        var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next()
        first.send(.disappeared); gate.release(); await first.viewModel.settle()
        let next = ContactsCoordinator(repository: fake, account: "a", mode: .profile("peer"), navigate: { _ in })
        next.send(.refresh); await next.viewModel.settle()
        #expect(next.viewModel.state.unknownMutation)
        #expect(next.viewModel.state.pendingMutation?.arguments == .add("peer"))
        #expect(next.viewModel.state.pendingMutation?.operationID == (await fake.attempts).first?.0)
        next.send(.principal("different")); next.send(.add); await next.viewModel.settle(); #expect(await fake.attempts.count == 1)
        next.send(.disappeared)
    }
    @Test func onlyIncomingPendingRequestsCanBeSelectedAndNoDecisionBeforeConfirm() async {
        let fake = ContactsFake(); let model = ContactsViewModel(repository: fake, account: "a", emit: { _ in })
        model.send(.refresh); await model.settle()
        model.send(.requestDecision("outgoing", .accept)); #expect(model.state.pending == nil)
        model.send(.requestDecision("incoming", .decline)); #expect(model.state.pending?.request.id == "incoming"); #expect(await fake.decisions.isEmpty)
        model.send(.confirmDecision); await model.settle(); #expect(await fake.decisions == ["incoming:decline"])
        model.send(.disappeared); #expect(model.state.requests.isEmpty)
    }
    @Test func unknownMutationPreventsFreshMutationAndUnsupportedReplyNeverAccepts() async {
        let fake = ContactsFake(); let model = ContactsViewModel(repository: fake, account: "a", emit: { _ in })
        model.send(.refresh); await model.settle(); model.send(.unavailable(.replyWithoutAcceptance)); #expect(await fake.decisions.isEmpty)
        model.send(.principal("peer")); model.send(.add); await model.settle()
        #expect(model.state.unknownMutation)
        model.send(.requestDecision("incoming", .accept)); #expect(model.state.pending == nil)
        model.send(.disappeared)
    }
    @Test func unavailableRepositoryDoesNotFabricateContactOrVerification() async {
        let model = ContactsViewModel(repository: UnavailableContactsRepository(), account: "a", emit: { _ in })
        model.send(.refresh); await model.settle()
        #expect(model.state.contacts.isEmpty); #expect(model.state.safety == nil); #expect(model.state.failure == .sdkUnavailable)
        model.send(.disappeared)
    }
}
