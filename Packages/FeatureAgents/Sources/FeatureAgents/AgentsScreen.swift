// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct AgentsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: AgentsState
    public let onAction: (AgentsAction) -> Void
    public init(state: AgentsState, onAction: @escaping (AgentsAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureAgentsStrings.text("agents." + key, locale: locale) }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(copy("title"), large: true, latin: true, tag: "agents-header")
            KitTipBar(copy("desktop"), icon: "info", tag: "agents-desktop")
            if state.loading { ProgressView(copy("loading")) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if state.failure == nil && !state.loading {
                VStack(alignment: .leading, spacing: theme.gap) {
                    KitStatusHero(icon: "search-x", tag: "agents-empty")
                    Text(copy("empty.title")).font(theme.bodyFont.weight(.semibold))
                    Text(copy("empty.message")).font(theme.captionFont).foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            }
            Text(copy("explanation")).font(theme.captionFont)
            if state.mode != .directory { Button(copy("directory")) { onAction(.mode(.directory)) } }
            Button(copy("retry")) { onAction(.retry) }.disabled(state.loading)
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
        .rfHidesNavigationBar()
        .privacySensitive()
    }
}
