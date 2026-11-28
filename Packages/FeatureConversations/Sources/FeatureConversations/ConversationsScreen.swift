// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization
public struct ConversationsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @State private var showingMore = false
    public let state: ConversationsState
    public let onAction: (ConversationsAction) -> Void
    public init(state: ConversationsState, onAction: @escaping (ConversationsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitPageHeader(
                FeatureConversationsStrings.text("common.tab.messages", locale: locale),
                large: true,
                subtitle: accountSubtitle,
                actions: [
                    KitHeaderAction(icon: "square-pen", label: FeatureConversationsStrings.text("conversations.action.new", locale: locale), action: { onAction(.newConversation) }),
                    KitHeaderAction(icon: "ellipsis", label: FeatureConversationsStrings.text("conversations.action.more", locale: locale), action: { showingMore = true }),
                ],
                tag: "messages-header"
            )
            switch content {
            case .loading:
                searchField
                ConversationsSkeleton()
                Spacer(minLength: 0)
            case .failure(let failure):
                searchField
                ConversationsFailure(failure: failure) { onAction(.refresh) }
                Spacer(minLength: 0)
            case .empty:
                ConversationsEmpty { onAction(.addContact) }
                Spacer(minLength: 0)
            case .list:
                searchField
                list
            }
        } }
        .confirmationDialog(FeatureConversationsStrings.text("conversations.action.more", locale: locale), isPresented: $showingMore) {
            Button(FeatureConversationsStrings.text("contacts.strangers.title", locale: locale)) { onAction(.strangers) }
            Button(FeatureConversationsStrings.text("common.tab.contacts", locale: locale)) { onAction(.contacts) }
        }
        .rfHidesNavigationBar()
        .privacySensitive()
    }
    /// What the area under the header shows. Skeleton and centred states only replace an empty list;
    /// once rows are loaded a refresh or a failure keeps them visible.
    enum Content: Equatable { case loading, failure(AppFailure), empty, list }
    var content: Content {
        let strangers = (state.strangersUnread ?? 0) > 0
        if state.rows.isEmpty && !strangers {
            if let failure = state.failure { return .failure(failure) }
            if state.loading { return .loading }
            return .empty
        }
        return .list
    }
    private var searchField: some View {
        KitSearchField(value: Binding(get: { state.query }, set: { onAction(.queryChanged($0)) }), placeholder: FeatureConversationsStrings.text("conversations.search.placeholder", locale: locale), tag: "message-search")
            .padding(.horizontal, theme.gap)
            .padding(.top, 20)
            .padding(.bottom, 12)
    }
    private var list: some View {
        ScrollView { LazyVStack(spacing: 0) {
            if let failure = state.failure {
                RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) { onAction(.refresh) }
                    .padding(.horizontal, theme.gap).padding(.bottom, theme.gap)
            }
            KitConversationRow(
                FeatureConversationsStrings.text("contacts.strangers.title", locale: locale),
                preview: FeatureConversationsStrings.pendingRequests(state.strangersUnread ?? 0, locale: locale),
                time: "",
                badge: badge(state.strangersUnread),
                tag: "strangers",
                action: { onAction(.strangers) }
            ) {
                KitAvatar("", size: 44, kind: .person, icon: "user-round", tag: "strangers-avatar")
            }
            if shownRows.isEmpty && !state.query.isEmpty {
                Text(FeatureConversationsStrings.text("conversations.search.empty", locale: locale)).foregroundStyle(theme.secondary).padding(theme.gap).accessibilityIdentifier("message-search-empty")
            }
            ForEach(shownRows) { row in
                KitConversationRow(
                    row.title,
                    preview: row.preview,
                    time: row.timeLabel,
                    sender: row.sender.isEmpty ? nil : row.sender,
                    muted: row.muted,
                    pinned: row.pinned,
                    read: row.readReceipt,
                    badge: badge(row.unreadCount),
                    aiMarker: row.classification.isAIAgent,
                    tag: row.id,
                    action: { onAction(.open(row.id)) }
                ) {
                    rowAvatar(row)
                }
                .onAppear {
                    if row.id == state.rows.last?.id { onAction(.loadMore) }
                    if row.id == state.rows.first?.id && state.canLoadBefore { onAction(.loadBefore) }
                }
            }
            if state.loadingMore { ProgressView(FeatureConversationsStrings.text("conversations.loadingMore", locale: locale)).padding(theme.gap) }
            if state.canLoadMore || state.rows.count > ConversationsWindow.pageSize {
                Text(FeatureConversationsStrings.text("conversations.order.note", locale: locale)).font(.footnote).foregroundStyle(theme.secondary).padding(theme.gap)
            }
        } }
        .refreshable { onAction(.refresh) }
    }
    /// The loaded chats whose title contains the query, ignoring case, accents and width; all of them while the field is empty.
    private var shownRows: [ConversationRecord] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return state.rows }
        return state.rows.filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
    }
    private var accountSubtitle: String? {
        let name = state.accountTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return FeatureConversationsStrings.sentence("conversations.account.subtitle", [.untrusted(name)], locale: locale)
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
