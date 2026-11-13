// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureConversations
private actor DirectoryFake: ConversationsRepository {
    var failure: AppFailure?
    func fail() { failure = .offline }
    func list(account: String) -> RepositoryResult<[ConversationRecord]> { if let failure { return .failure(failure) }; return .success([ConversationRecord(id: "thread", title: "Thread", preview: "")]) }
    func search(account: String, query: String) -> RepositoryResult<[ConversationRecord]> { .failure(.notAvailable("Search unavailable")) }
    func observe(account: String) -> RepositoryObservation { RepositoryObservation(stream: AsyncStream { $0.finish() }) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct ConversationsViewModelTests {
    @Test func listsOnlyRepositoryRecordsAndNavigationChecksIdentity() async {
        let repository = DirectoryFake(); var events: [ConversationsEvent] = []
        let model = ConversationsViewModel(repository: repository, account: "a", emit: { events.append($0) })
        model.send(.refresh); await model.settle()
        #expect(model.state.rows.map(\.id) == ["thread"])
        model.send(.open("unknown")); #expect(events.isEmpty)
        model.send(.open("thread")); #expect(events == [.navigate(.conversation("thread"))])
        model.send(.disappeared); #expect(model.state.rows.isEmpty)
    }
    @Test func offlineRefreshPreservesConfirmedRowsAndSearchIsTypedUnavailable() async {
        let repository = DirectoryFake(); let model = ConversationsViewModel(repository: repository, account: "a", emit: { _ in })
        model.send(.refresh); await model.settle()
        await repository.fail(); model.send(.refresh); await model.settle()
        #expect(model.state.failure == .offline); #expect(model.state.rows.count == 1)
        model.send(.queryChanged("text")); model.send(.search); await model.settle()
        #expect(model.state.failure == .notAvailable("Search unavailable")); #expect(model.state.rows.count == 1)
        model.send(.disappeared)
    }
    @Test func unavailableHasNoRecords() async {
        let model = ConversationsViewModel(repository: UnavailableConversationsRepository(), account: "a", emit: { _ in })
        model.send(.refresh); await model.settle()
        #expect(model.state.rows.isEmpty); #expect(model.state.failure == .sdkUnavailable)
        model.send(.disappeared)
    }
}
