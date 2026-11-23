// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import AppData
@testable import FeatureAgents
/// 50,000 agents paged by the SDK cursor, plus recorded mutations.
private final class SyntheticAgents: AgentsRepository, Sendable {
    let calls = Mutex<[String]>([])
    let total: Int
    init(total: Int = 50_000) { self.total = total }
    private func agent(_ index: Int, name: String? = nil) -> AgentRecord {
        AgentRecord(id: String(format: "a%05d", index), persona: AgentPersona(name: name ?? "Agent \(index)", avatar: "orbit", responsibility: "r\(index)"), lifecycle: "active", role: "assistant",
                    access: AgentAccess(dm: "contacts", groupInviters: "owner", allowedHumans: []))
    }
    func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<AgentPage> {
        let start = cursor.flatMap(Int.init) ?? 0, end = min(start + limit, total)
        return .success(AgentPage(page: RowPage(rows: (start..<end).map { agent($0) }, nextCursor: end < total ? String(end) : nil), journalCursor: "j1"))
    }
    func record(account: String, agent id: String) async -> RepositoryResult<AgentRecord> { .success(agent(Int(id.dropFirst()) ?? 0)) }
    func changes(account: String, since journalCursor: String) async -> RepositoryResult<AgentPage> {
        calls.withLock { $0.append("watch:" + journalCursor) }
        return .success(AgentPage(page: RowPage(rows: [agent(1, name: "Renamed")], nextCursor: nil), journalCursor: "j2"))
    }
    func editPersona(account: String, agent id: String, persona: AgentPersona) async -> RepositoryResult<AgentRecord> {
        calls.withLock { $0.append("edit:" + id + ":" + persona.name) }
        return .success(AgentRecord(id: id, persona: persona, lifecycle: "active", role: "assistant", access: AgentAccess(dm: "contacts", groupInviters: "owner", allowedHumans: [])))
    }
    func delete(account: String, agent id: String) async -> RepositoryResult<AgentRecord> { calls.withLock { $0.append("delete:" + id) }; return .success(agent(Int(id.dropFirst()) ?? 0)) }
    func chatConversation(account: String, agent: String) async -> RepositoryResult<String> { .success("dm:" + agent) }
    func pendingCreation(account: String) async -> RepositoryResult<AgentCreationRequest?> { .success(AgentCreationRequest(id: "req", state: "pending", agentAnchor: nil, expiresAt: 1, failureReason: nil)) }
    func observe(account: String) async -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
    func unavailable(_ capability: AgentUnavailable) -> AppFailure { .unavailableResource("agents.unavailable." + capability.rawValue) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct AgentsViewModelTests {
    @Test func fiftyThousandAgentsPageThroughABoundedWindow() async {
        let source = SyntheticAgents(), model = AgentsViewModel(repository: source, account: "a", emit: { _ in })
        let clock = ContinuousClock()
        let first = await clock.measure { model.send(.retry); await model.settle() }
        #expect(model.state.entries.count == 50); #expect(model.state.canLoadMore); #expect(model.state.creation?.id == "req")
        var scroll = Duration.zero
        while model.state.canLoadMore { scroll += await clock.measure { model.send(.loadMore); await model.settle() }; #expect(model.state.entries.count <= 300) }
        #expect(model.state.entries.last?.id == "a49999")
        model.send(.query("Agent 4999")); #expect(model.state.entries.allSatisfy { $0.name.contains("Agent 4999") })
        print("AGENTS_50K first=\(first) scrollToEnd=\(scroll)")
        model.send(.disappeared)
    }
    @Test func editAndDeleteNeedConfirmationAndChatOpensTheConversation() async {
        let source = SyntheticAgents(total: 10); var events: [AgentsEvent] = []
        let model = AgentsViewModel(repository: source, account: "a", emit: { events.append($0) })
        model.send(.retry); await model.settle()
        model.send(.mode(.edit("a00002"))); await model.settle()
        #expect(model.state.draft.name == "Agent 2")
        model.send(.draftName("Nova")); model.send(.save); #expect(model.state.confirmingEdit); #expect(source.calls.withLock { $0 }.isEmpty)
        model.send(.confirmSave); await model.settle()
        #expect(source.calls.withLock { $0 } == ["edit:a00002:Nova"]); #expect(model.state.mode == .profile("a00002")); #expect(model.state.entries[2].name == "Nova")
        model.send(.delete); model.send(.cancelConfirmation); #expect(!model.state.confirmingDelete)
        model.send(.delete); model.send(.confirmDelete); await model.settle()
        #expect(source.calls.withLock { $0 }.last == "delete:a00002"); #expect(model.state.mode == .directory); #expect(!model.state.entries.contains { $0.id == "a00002" })
        model.send(.chat("a00001")); await model.settle(); #expect(events == [.navigate(.conversation("dm:a00001"))])
        model.send(.draftName("  ")); model.send(.mode(.edit("a00001"))); await model.settle(); model.send(.draftName(" ")); model.send(.save)
        #expect(model.state.failure == .invalidInput); #expect(!model.state.confirmingEdit)
        model.send(.disappeared)
    }
    @Test func missingSDKCapabilitiesAreTypedUnavailable() async {
        let model = AgentsViewModel(repository: SyntheticAgents(total: 1), account: "a", emit: { _ in })
        for capability in AgentUnavailable.allCases { model.send(.unavailable(capability)); #expect(model.state.failure == .unavailableResource("agents.unavailable." + capability.rawValue)) }
        let unavailable = AgentsViewModel(repository: UnavailableAgentsRepository(), account: "a", emit: { _ in })
        unavailable.send(.retry); await unavailable.settle(); #expect(unavailable.state.entries.isEmpty); #expect(unavailable.state.failure == .sdkUnavailable)
    }
}
