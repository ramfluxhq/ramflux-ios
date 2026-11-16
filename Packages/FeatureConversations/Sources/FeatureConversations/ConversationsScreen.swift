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
            KitPageHeader(
                FeatureConversationsStrings.text("copy.04d7b4833927", locale: locale),
                large: true,
                subtitle: state.accountID,
                actions: [
                    KitHeaderAction(icon: "user-round", label: FeatureConversationsStrings.text("copy.b450645debe2", locale: locale), action: { onAction(.contacts) }),
                    KitHeaderAction(icon: "refresh-cw", label: FeatureConversationsStrings.text("copy.0e9161011702", locale: locale), action: { onAction(.refresh) }),
                ],
                tag: "messages-header"
            )
            KitSearchField(value: Binding(get: { state.query }, set: { onAction(.queryChanged($0)) }), placeholder: FeatureConversationsStrings.text("copy.ddf0602b21a7", locale: locale), tag: "message-search")
                .padding(.horizontal, theme.gap)
                .onSubmit { onAction(.search) }
            if state.loading { ProgressView(FeatureConversationsStrings.text("copy.8d384c507b47", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) { onAction(.refresh) } }
            if state.rows.isEmpty && !state.loading && state.failure == nil { RFUnavailableView(title: FeatureConversationsStrings.text("copy.0d60084f056e", locale: locale), message: FeatureConversationsStrings.text("copy.10eb36925a11", locale: locale)) }
            ScrollView { LazyVStack(spacing: 0) {
                KitRow(FeatureConversationsStrings.text("copy.4ebdb8769377", locale: locale), action: { onAction(.strangers) }, icon: "user-round", tag: "strangers")
                ForEach(state.rows) { row in
                    KitConversationRow(row.title, preview: row.preview, time: "", badge: badge(row.unreadCount), tag: row.id, action: { onAction(.open(row.id)) }) {
                        KitAvatar(String(row.title.prefix(1)), size: 44, kind: .person, tag: row.id + "-avatar")
                    }
                }
            } }
        } }
        .rfHidesNavigationBar()
        .privacySensitive()
    }
    private func badge(_ count: UInt?) -> String? {
        guard let count, count > 0 else { return nil }
        return FeatureConversationsStrings.unread(count, locale: locale)
    }
}
