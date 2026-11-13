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
            HStack { Button("Strangers") { onAction(.strangers) }; Spacer(); Button("Contacts") { onAction(.contacts) } }.padding()
            if state.loading { ProgressView("Loading conversations") }
            if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) { onAction(.refresh) } }
            if state.rows.isEmpty && !state.loading && state.failure == nil { RFUnavailableView(title: "No conversations yet", message: "Add someone to your contacts to start a conversation.") }
            ScrollView { LazyVStack(spacing: 0) { ForEach(state.rows) { row in
                RFConversationRow(model: RFConversationRowModel(id: row.id, title: row.title, preview: row.preview, initial: String(row.title.prefix(1)), timestamp: "", unreadCount: row.unreadCount ?? 0), theme: RFTheme.adaptive(scheme)) { onAction(.open($0)) }
            } } }
        } }.navigationTitle("Messages").privacySensitive()
            .searchable(text: Binding(get: { state.query }, set: { onAction(.queryChanged($0)) }), prompt: "Search messages")
            .onSubmit(of: .search) { onAction(.search) }
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { onAction(.refresh) } }
    }
}
public struct ConversationsHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: ConversationsCoordinator
    public init(coordinator: ConversationsCoordinator) { self.coordinator = coordinator }
    public var body: some View { ConversationsScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, value in coordinator.send(value == .active ? .appeared : .disappeared) }
    }
}
public enum ConversationsPreviews {
    public static let states = [ConversationsState(), ConversationsState(loading: true), ConversationsState(failure: .offline), ConversationsState(rows: [ConversationRecord(id: "preview-thread", title: "Alex", preview: "See you tomorrow", unreadCount: 2)])]
}
#Preview("Inbox") { ConversationsScreen(state: ConversationsPreviews.states[3], onAction: { _ in }) }
