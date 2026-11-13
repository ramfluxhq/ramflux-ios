// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureChat
private actor ChatFake: ChatRepository {
    private(set) var attempts: [(String,String)] = []
    private(set) var deletes: [String] = []
    let journal = RetainedMutation<String, SendOutcome>()
    let gate: MutationGate?
    init(gate: MutationGate? = nil) { self.gate = gate }
    var succeed = false
    func completeNext() { succeed = true }
    nonisolated func unavailable(_ capability: ChatCapability) -> AppFailure { .unsupported }
    func messages(account: String, conversation: String) -> RepositoryResult<[MessageRecord]> { .success([MessageRecord(id: "m", sender: "peer", kind: .text("Message"), isOwn: false)]) }
    func sendState(account: String, conversation: String) async -> PendingChatSend? {
        guard let row = await journal.snapshot(scope: account + conversation) else { return nil }
        return PendingChatSend(operationID: row.operationID, text: row.arguments, unresolved: row.unresolved, result: row.result)
    }
    func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        await journal.run(scope: account + conversation, arguments: text, operationID: operationID) { await self.perform(text: text, operationID: operationID) }
    }
    private func perform(text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        attempts.append((operationID,text)); if attempts.count == 1, let gate { await gate.wait() }
        return succeed ? .success(SendOutcome(messageID: "m", state: .submitted)) : .failure(.outcomeUnknown)
    }
    func delete(account: String, conversation: String, message: String, operationID: String) -> RepositoryResult<Void> { deletes.append(message); return .success(()) }
    func observe(account: String) -> RepositoryObservation { {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }() }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct ChatViewModelTests {
    @Test func cancellationAndChatReplacementRestoreOriginalPendingSend() async {
        let gate = MutationGate(), fake = ChatFake(gate: gate)
        defer { gate.release() }
        let a = ChatCoordinator(repository: fake, account: "a", conversation: "A")
        a.send(.draftChanged("Original")); a.send(.send)
        var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next()
        a.send(.conceal)
        let b = ChatCoordinator(repository: fake, account: "a", conversation: "B"); b.send(.refresh); await b.viewModel.settle()
        #expect(b.viewModel.state.pendingSend == nil)
        gate.release(); await a.viewModel.settle()
        let returned = ChatCoordinator(repository: fake, account: "a", conversation: "A"); returned.send(.refresh); await returned.viewModel.settle()
        #expect(returned.viewModel.state.pendingSend?.text == "Original")
        #expect(returned.viewModel.state.pendingSend?.operationID == (await fake.attempts).first?.0)
        returned.send(.draftChanged("Different")); returned.send(.send); await returned.viewModel.settle(); #expect(await fake.attempts.count == 1)
        await fake.completeNext(); returned.send(.retrySameSend); await returned.viewModel.settle()
        let attempts = await fake.attempts; #expect(attempts.count == 2); #expect(attempts.first?.0 == attempts.last?.0); #expect(attempts.last?.1 == "Original")
        returned.send(.conceal); b.send(.conceal)
    }
    @Test func successfulBackgroundSendClearsOnlyItsRestoredDraftAndCannotResend() async {
        for edited in [false, true] {
            let gate = MutationGate(), fake = ChatFake(gate: gate); defer { gate.release() }
            let original = ChatCoordinator(repository: fake, account: "a", conversation: "A")
            original.send(.draftChanged("Original")); original.send(.send)
            var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next(); original.send(.conceal)
            let b = ChatCoordinator(repository: fake, account: "a", conversation: "B"); b.send(.refresh); await b.viewModel.settle()
            let returned = ChatCoordinator(repository: fake, account: "a", conversation: "A"); returned.send(.refresh); await returned.viewModel.settle()
            #expect(returned.viewModel.state.draft == "Original"); #expect(returned.viewModel.state.pendingSend != nil)
            if edited { returned.send(.draftChanged("Edited")) }
            await fake.completeNext(); gate.release(); await original.viewModel.settle()
            returned.send(.refresh); await returned.viewModel.settle()
            #expect(returned.viewModel.state.pendingSend == nil); #expect(returned.viewModel.state.draft == (edited ? "Edited" : ""))
            if !edited { returned.send(.send); await returned.viewModel.settle(); #expect(await fake.attempts.count == 1) }
            returned.send(.conceal); b.send(.conceal)
        }
    }
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
