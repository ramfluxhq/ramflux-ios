// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum AgentsPreviews {
    public static var states: [AgentsState] { AgentCapability.allCases.map { mode in
        var state = AgentsState(mode: mode); state.failure = .unavailableResource("agents.unavailable"); return state
    } }
}
#Preview("Agents") { RFThemeScope { AgentsScreen(state: AgentsPreviews.states[0], onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(AgentsPreviews.states.indices, id: \.self) { index in AgentsScreen(state: AgentsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(AgentsPreviews.states.indices, id: \.self) { index in AgentsScreen(state: AgentsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
