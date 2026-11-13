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
            RFPageHeader(title: copy("title"), subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { Button(copy("create")) { onAction(.mode(.create)) } })
            Text(copy(state.mode.rawValue)).font(theme.pageFont)
            if state.loading { ProgressView(copy("loading")) }
            if let failure = state.failure { RFUnavailableView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if state.mode == .create || state.mode == .edit || state.mode == .goal {
                RFTextField(id: "agent-name", label: copy("name"), value: Binding(get: { state.draft.name }, set: { onAction(.name($0)) }), theme: theme)
                RFTextField(id: "agent-goal", label: copy("goal"), value: Binding(get: { state.draft.goal }, set: { onAction(.goal($0)) }), theme: theme)
                if state.mode == .create { Button(copy("create")) { onAction(.create) }.disabled(state.loading || state.draft.name.isEmpty) }
            }
            Text(copy("explanation")).font(theme.captionFont)
            if state.mode != .directory { Button(copy("directory")) { onAction(.mode(.directory)) } }
            Button(copy("retry")) { onAction(.retry) }.disabled(state.loading)
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }.privacySensitive()
    }
}
