// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureContacts
private actor ContactsFake: ContactsRepository {
    private(set) var decisions: [String] = []
    func contacts(account: String) -> RepositoryResult<[ContactRecord]> { .success([]) }
    func requests(account: String) -> RepositoryResult<[ContactRequestRecord]> { .success([
        ContactRequestRecord(id: "incoming", principal: "peer", name: "Peer", direction: "inbound", state: "pending"),
        ContactRequestRecord(id: "outgoing", principal: "peer", name: "Peer", direction: "outbound", state: "pending"),
    ]) }
    func add(account: String, principal: String, operationID: String) -> RepositoryResult<Void> { .failure(.outcomeUnknown) }
    func decide(account: String, request: String, decision: ContactDecision, operationID: String) -> RepositoryResult<Void> { decisions.append(request + ":" + decision.rawValue); return .success(()) }
    func safety(account: String, contact: ContactRecord) -> RepositoryResult<ContactSafety> { .failure(.unsupported) }
    func observe(account: String) -> RepositoryObservation { RepositoryObservation(stream: AsyncStream { $0.finish() }) }
    nonisolated func unavailable(_ capability: ContactUnavailable) -> AppFailure { .unsupported }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct ContactsViewModelTests {
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
