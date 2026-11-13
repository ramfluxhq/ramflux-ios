// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureChat
private actor ChatFake: ChatRepository {
    private(set) var attempts: [(String,String)] = []
    private(set) var deletes: [String] = []
    var succeed = false
    func completeNext() { succeed = true }
    nonisolated func unavailable(_ capability: ChatCapability) -> AppFailure { .unsupported }
    func messages(account: String, conversation: String) -> RepositoryResult<[MessageRecord]> { .success([MessageRecord(id: "m", sender: "peer", kind: .text("Message"), isOwn: false)]) }
    func send(account: String, conversation: String, text: String, operationID: String) -> RepositoryResult<SendOutcome> {
        attempts.append((operationID,text)); return succeed ? .success(SendOutcome(messageID: "m", state: .submitted)) : .failure(.outcomeUnknown)
    }
    func delete(account: String, conversation: String, message: String, operationID: String) -> RepositoryResult<Void> { deletes.append(message); return .success(()) }
    func observe(account: String) -> RepositoryObservation { RepositoryObservation(stream: AsyncStream { $0.finish() }) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct ChatViewModelTests {
    @Test func unknownSendPreservesDraftAndExplicitRetryKeepsExactOperationAndText() async {
        let fake = ChatFake(); let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.draftChanged("Original")); model.send(.send); await model.settle()
        #expect(model.state.draft == "Original"); #expect(model.state.failure == .outcomeUnknown)
        model.send(.draftChanged("New draft")); model.send(.send); await model.settle()
        #expect(await fake.attempts.count == 1)
        await fake.completeNext(); model.send(.retrySameSend); await model.settle()
        let attempts = await fake.attempts
        #expect(attempts.count == 2); #expect(attempts.first?.0 == attempts.last?.0); #expect(attempts.last?.1 == "Original")
        #expect(model.state.draft == "New draft"); #expect(model.state.pendingSend == nil)
        model.send(.conceal); #expect(model.state.draft.isEmpty); #expect(model.state.messages.isEmpty)
    }
    @Test func deletionRequiresKnownSelectionThenExplicitConfirmation() async {
        let fake = ChatFake(); let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.refresh); await model.settle()
        model.send(.requestDelete("unknown")); model.send(.confirmDelete); await model.settle(); #expect(await fake.deletes.isEmpty)
        model.send(.requestDelete("m")); #expect(await fake.deletes.isEmpty)
        model.send(.confirmDelete); await model.settle(); #expect(await fake.deletes == ["m"])
        model.send(.disappeared)
    }
    @Test func unavailableSendNeverAppendsAFakeMessageOrClearsDraft() async {
        let model = ChatViewModel(repository: UnavailableChatRepository(), account: "a", conversation: "c", emit: { _ in })
        model.send(.draftChanged("Keep")); model.send(.send); await model.settle()
        #expect(model.state.messages.isEmpty); #expect(model.state.draft == "Keep"); #expect(model.state.failure == .sdkUnavailable)
    }
}
