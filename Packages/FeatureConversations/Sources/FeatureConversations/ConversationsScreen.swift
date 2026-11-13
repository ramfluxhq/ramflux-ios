// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ConversationsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: ConversationsState
    public let onAction: (ConversationsAction) -> Void
    public init(state: ConversationsState, onAction: @escaping (ConversationsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            ConversationsHeader(title: FeatureConversationsStrings.text("copy.04d7b4833927", locale: locale), account: state.accountID, theme: theme, actions: { Button(FeatureConversationsStrings.text("copy.b450645debe2", locale: locale), systemImage: "person.crop.circle") { onAction(.contacts) } })
            RFSearchField(id: "message-search", label: FeatureConversationsStrings.text("copy.ddf0602b21a7", locale: locale), value: Binding(get: { state.query }, set: { onAction(.queryChanged($0)) }), theme: theme).padding(.horizontal, theme.gap).onSubmit { onAction(.search) }
            if state.loading { ProgressView(FeatureConversationsStrings.text("copy.8d384c507b47", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) { onAction(.refresh) } }
            if state.rows.isEmpty && !state.loading && state.failure == nil { RFUnavailableView(title: FeatureConversationsStrings.text("copy.0d60084f056e", locale: locale), message: FeatureConversationsStrings.text("copy.10eb36925a11", locale: locale)) }
            ScrollView { LazyVStack(spacing: 0) {
                Button { onAction(.strangers) } label: { RFIdentityRow(id: "strangers", title: FeatureConversationsStrings.text("copy.4ebdb8769377", locale: locale), subtitle: "", theme: theme, avatar: { Image(systemName: "person.crop.circle.badge.questionmark") }, badge: { EmptyView() }, trailing: { Image(systemName: "chevron.right") }) }.buttonStyle(.plain)
                ForEach(state.rows) { row in
                RFConversationRow(model: RFConversationRowModel(id: row.id, title: row.title, preview: row.preview, initial: String(row.title.prefix(1)), timestamp: "", unreadCount: row.unreadCount ?? 0, unreadAccessibilityValue: FeatureConversationsStrings.unread(row.unreadCount ?? 0, locale: locale)), theme: theme) { onAction(.open($0)) }
            } } }
        } }.navigationTitle(FeatureConversationsStrings.text("copy.04d7b4833927", locale: locale)).privacySensitive()
            .toolbar { Button(FeatureConversationsStrings.text("copy.0e9161011702", locale: locale), systemImage: "arrow.clockwise") { onAction(.refresh) } }
    }
}
