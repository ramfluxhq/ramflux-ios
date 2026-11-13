// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureAgents
@Suite(.timeLimit(.minutes(1))) @MainActor struct AgentsViewModelTests {
    @Test func everyAgentCapabilityIsExplicitlyUnavailableWithoutFakeSuccess() async {
        var events: [AgentsEvent] = []
        let vm = AgentsViewModel(repository: UnavailableAgentsRepository(), account: "a", emit: { events.append($0) })
        for mode in AgentCapability.allCases { vm.send(.mode(mode)); await vm.settle(); #expect(vm.state.failure != nil); #expect(!vm.state.loading) }
        vm.send(.mode(.create)); await vm.settle(); vm.send(.name("Research")); vm.send(.goal("Review")); vm.send(.create); await vm.settle()
        #expect(vm.state.failure != nil); #expect(events.isEmpty); vm.send(.disappeared); #expect(vm.state.draft == AgentDraft())
    }
    @Test func concealFencesLateAvailabilityAndDraftInputsAreBounded() async {
        let vm = AgentsViewModel(repository: UnavailableAgentsRepository(), account: "a", emit: { _ in })
        vm.send(.name(String(repeating: "x", count: 300))); #expect(vm.state.draftIssue == .nameLimit)
        vm.send(.appeared); vm.send(.disappeared); await vm.settle(); #expect(vm.state == AgentsState())
    }
    @Test func nameScalarAndResponsibilityByteBoundsMatchFinalContract() {
        var draft = AgentDraft(); draft.name = String(repeating: "界", count: 40); draft.goal = String(repeating: "a", count: 256); #expect(draft.issue == nil)
        draft.name += "界"; #expect(draft.issue == .nameLimit)
        draft.name = "Research"; draft.goal = String(repeating: "界", count: 85); #expect(draft.issue == nil)
        draft.goal += "界"; #expect(draft.issue == .goalLimit)
        draft.goal = ""; #expect(draft.issue == .goalRequired)
    }
}
