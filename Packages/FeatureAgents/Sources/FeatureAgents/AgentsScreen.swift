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
        RFPage {
            VStack(spacing: 0) {
                KitPageHeader(AppTab.agents.title(locale: locale), large: true, latin: true, tag: "agents-header")
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.gap) {
                        if state.loading { ProgressView(copy("loading")).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, theme.gap) }
                        if let failure = state.failure {
                            RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale))
                                .padding(.horizontal, theme.gap)
                        }
                        if showingDirectory {
                            KitSearchField(value: $query, placeholder: copy("search"), tag: "agents-search")
                                .padding(.horizontal, theme.gap)
                            if shown.isEmpty {
                                searchMiss.padding(.horizontal, theme.gap)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(shown) { entry in
                                        KitConversationRow(entry.name, preview: entry.detail, time: "", tag: "agent-" + entry.id) {
                                            KitAvatar("", size: 44, kind: .agent, icon: entry.icon, tag: entry.id + "-avatar")
                                        }
                                    }
                                }
                                Text(copy("directory.note")).font(theme.captionFont).foregroundStyle(theme.secondary).padding(.horizontal, theme.gap).padding(.top, 12)
                                multiAgentLink.padding(.top, 12)
                            }
                        } else if state.failure == nil && !state.loading {
                            KitTipBar(copy("desktop"), icon: "info", tag: "agents-desktop").padding(.horizontal, theme.gap)
                            searchMiss.padding(.horizontal, theme.gap)
                            Text(copy("explanation")).font(theme.captionFont).padding(.horizontal, theme.gap)
                            if state.mode != .directory { Button(copy("directory")) { onAction(.mode(.directory)) }.padding(.horizontal, theme.gap) }
                            Button(copy("retry")) { onAction(.retry) }.disabled(state.loading).padding(.horizontal, theme.gap)
                        }
                    }
                    .padding(.vertical, theme.gap)
                    .frame(maxWidth: theme.column_max, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .rfHidesNavigationBar()
        .privacySensitive()
    }
    private var multiAgentLink: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                KitIcon(name: "users-round", size: 20, tint: theme.text)
                Text(copy("multi"))
                    .font(.custom(theme.font, size: theme.size_mobile_body).weight(.medium))
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.gap)
        .accessibilityIdentifier("agents-multi")
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
