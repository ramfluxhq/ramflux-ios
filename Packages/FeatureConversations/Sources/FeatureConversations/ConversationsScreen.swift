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
                subtitle: accountSubtitle,
                actions: [
                    KitHeaderAction(icon: "user-round", label: FeatureConversationsStrings.text("copy.b450645debe2", locale: locale), action: { onAction(.contacts) }),
                    KitHeaderAction(icon: "refresh-cw", label: FeatureConversationsStrings.text("copy.0e9161011702", locale: locale), action: { onAction(.refresh) }),
                ],
                tag: "messages-header"
            )
            KitSearchField(value: Binding(get: { state.query }, set: { onAction(.queryChanged($0)) }), placeholder: FeatureConversationsStrings.text("copy.ddf0602b21a7", locale: locale), tag: "message-search")
                .padding(.horizontal, theme.gap)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .onSubmit { onAction(.search) }
            if state.loading { ProgressView(FeatureConversationsStrings.text("copy.8d384c507b47", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) { onAction(.refresh) } }
            if state.rows.isEmpty && state.strangersDetail.isEmpty && !state.loading && state.failure == nil { RFUnavailableView(title: FeatureConversationsStrings.text("copy.0d60084f056e", locale: locale), message: FeatureConversationsStrings.text("copy.10eb36925a11", locale: locale)) }
            ScrollView { LazyVStack(spacing: 0) {
                KitConversationRow(
                    FeatureConversationsStrings.text("copy.4ebdb8769377", locale: locale),
                    preview: state.strangersDetail,
                    time: "",
                    badge: badge(state.strangersUnread),
                    tag: "strangers",
                    action: { onAction(.strangers) }
                ) {
                    KitAvatar("", size: 44, kind: .person, icon: "user-round", tag: "strangers-avatar")
                }
                ForEach(state.rows) { row in
                    KitConversationRow(
                        row.title,
                        preview: row.preview,
                        time: row.timeLabel,
                        sender: row.sender.isEmpty ? nil : row.sender,
                        muted: row.muted,
                        pinned: row.pinned,
                        read: row.readReceipt,
                        badge: badge(row.unreadCount),
                        tag: row.id,
                        action: { onAction(.open(row.id)) }
                    ) {
                        rowAvatar(row)
                    }
                }
            } }
        } }
        .rfHidesNavigationBar()
        .privacySensitive()
    }
    private var accountSubtitle: String? {
        let name = state.accountTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let current = FeatureConversationsStrings.text("conversations.account.current", locale: locale)
        return name + " · " + current
    }
    private func badge(_ count: UInt?) -> String? {
        guard let count, count > 0 else { return nil }
        return count.formatted(.number.locale(locale))
    }
    private func rowAvatar(_ row: ConversationRecord) -> some View {
        let kind: KitAvatarKind = switch row.kind {
        case "agent": .agent
        case "channel": .channel
        default: .person
        }
        let label = kind == .person ? String(row.title.prefix(1)) : ""
        return KitAvatar(label, size: 44, kind: kind, icon: row.avatarIcon.isEmpty ? "orbit" : row.avatarIcon, tag: row.id + "-avatar")
    }
}
