// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum AgentsPreviews {
    /// Illustrative preview states only; production state comes from the agents repository.
    public static var states: [AgentsState] {
        let agent = AgentRecord(id: "preview-agent", persona: AgentPersona(name: "Nova", avatar: "orbit", responsibility: "Summarises the week"), lifecycle: "active", role: "assistant",
                                access: AgentAccess(dm: "contacts", groupInviters: "owner", allowedHumans: []))
        var directory = AgentsState(); directory.entries = [AgentEntry(id: agent.id, name: "Nova", detail: "Summarises the week", icon: "orbit")]
        directory.creation = AgentCreationRequest(id: "preview-request", state: "pending", agentAnchor: nil, expiresAt: 1_800_000_000, failureReason: nil)
        var profile = AgentsState(mode: .profile(agent.id)); profile.selected = agent
        var edit = AgentsState(mode: .edit(agent.id)); edit.selected = agent; edit.draft = agent.persona
        return [AgentsState(), directory, profile, edit]
    }
}
#Preview("Agents") { RFThemeScope { AgentsScreen(state: AgentsPreviews.states[0], onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(AgentsPreviews.states.indices, id: \.self) { index in AgentsScreen(state: AgentsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(AgentsPreviews.states.indices, id: \.self) { index in AgentsScreen(state: AgentsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
