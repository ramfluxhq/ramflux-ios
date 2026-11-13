// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ConversationsScreen: View {
    @Environment(\.colorScheme) private var scheme
    public let state: ConversationsState
    public let onAction: (ConversationsAction) -> Void
    public init(state: ConversationsState, onAction: @escaping (ConversationsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            RFPageHeader(title: "Messages", subtitle: "", theme: RFTheme.adaptive(scheme), leading: { EmptyView() }, trailing: { EmptyView() })
            RFSearchField(id: "message-search", label: "Search messages", value: Binding(get: { state.query }, set: { onAction(.queryChanged($0)) }), theme: RFTheme.adaptive(scheme)).padding(.horizontal).onSubmit { onAction(.search) }
            HStack { Button("Strangers") { onAction(.strangers) }; Spacer(); Button("Contacts") { onAction(.contacts) } }.padding()
            if state.loading { ProgressView("Loading conversations") }
            if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) { onAction(.refresh) } }
            if state.rows.isEmpty && !state.loading && state.failure == nil { RFUnavailableView(title: "No conversations yet", message: "Add someone to your contacts to start a conversation.") }
            ScrollView { LazyVStack(spacing: 0) { ForEach(state.rows) { row in
                RFConversationRow(model: RFConversationRowModel(id: row.id, title: row.title, preview: row.preview, initial: String(row.title.prefix(1)), timestamp: "", unreadCount: row.unreadCount ?? 0), theme: RFTheme.adaptive(scheme)) { onAction(.open($0)) }
            } } }
        } }.navigationTitle("Messages").privacySensitive()
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { onAction(.refresh) } }
    }
}
