// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct AgentsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @State private var query = ""
    public let state: AgentsState
    public let onAction: (AgentsAction) -> Void
    public init(state: AgentsState, onAction: @escaping (AgentsAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureAgentsStrings.text("agents." + key, locale: locale) }
    private var showingDirectory: Bool { state.failure == nil && !state.loading && !state.entries.isEmpty }
    private var shown: [AgentEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return state.entries }
        return state.entries.filter { $0.name.localizedStandardContains(needle) }
    }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(AppTab.agents.title(locale: locale), large: true, latin: true, tag: "agents-header")
            KitTipBar(copy("desktop"), icon: "info", tag: "agents-desktop")
            if state.loading { ProgressView(copy("loading")) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if showingDirectory {
                KitSearchField(value: $query, placeholder: copy("search"), tag: "agents-search")
                if shown.isEmpty {
                    searchMiss
                } else {
                    ForEach(shown) { entry in
                        KitConversationRow(entry.name, preview: entry.detail, time: "", tag: "agent-" + entry.id) {
                            KitAvatar("", size: 44, kind: .agent, icon: entry.icon, tag: entry.id + "-avatar")
                        }
                    }
                    Text(copy("directory.note")).font(theme.captionFont).foregroundStyle(theme.secondary)
                }
            } else if state.failure == nil && !state.loading {
                searchMiss
            }
            if !showingDirectory {
                Text(copy("explanation")).font(theme.captionFont)
                if state.mode != .directory { Button(copy("directory")) { onAction(.mode(.directory)) } }
                Button(copy("retry")) { onAction(.retry) }.disabled(state.loading)
            }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
        .rfHidesNavigationBar()
        .privacySensitive()
    }
    private var searchMiss: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            KitStatusHero(icon: "search-x", tag: "agents-empty")
            Text(copy("empty.title")).font(theme.bodyFont.weight(.semibold))
            Text(copy("empty.message")).font(theme.captionFont).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
