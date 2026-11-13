// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ChatScreen: View {
    @Environment(\.colorScheme) private var scheme
    public let state: ChatState
    public let onAction: (ChatAction) -> Void
    public init(state: ChatState, onAction: @escaping (ChatAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            RFChatHeader(id: state.conversationID, title: state.conversationID, subtitle: "", theme: RFTheme.adaptive(scheme), leading: { EmptyView() }, trailing: { EmptyView() })
            if state.loading { ProgressView("Loading messages") }
            if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) }
            if state.messages.isEmpty && !state.loading { RFUnavailableView(title: "No messages yet", message: "Messages in this conversation will appear here.") }
            #if os(iOS)
            ChatTimeline(messages: state.messages, onAction: onAction)
            #else
            ScrollView { LazyVStack { ForEach(state.messages) { MessageBubble(message: $0, onAction: onAction) } } }
            #endif
            if let outcome = state.lastSubmission { Text(outcome.state == .submitted ? "Submitted to account service" : "Delivery failed").font(.caption) }
            if state.pendingSend != nil && !state.sending { Button("Retry original send") { onAction(.retrySameSend) } }
            #if os(iOS)
            ChatComposer(text: Binding(get: { state.draft }, set: { onAction(.draftChanged($0)) }), enabled: !state.sending && state.pendingSend == nil) { onAction(.send) }
                .frame(minHeight: 52, maxHeight: 140)
            #else
            TextField("Message", text: Binding(get: { state.draft }, set: { onAction(.draftChanged($0)) }))
            Button("Send") { onAction(.send) }.disabled(state.sending || state.pendingSend != nil)
            #endif
        } }.privacySensitive()
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { onAction(.refresh) } }
            .confirmationDialog("Delete from your own devices?", isPresented: Binding(get: { state.pendingDelete != nil }, set: { if !$0 { onAction(.cancelDelete) } })) {
                Button("Delete message", role: .destructive) { onAction(.confirmDelete) }
            } message: { Text("This does not erase copies on other people's devices.") }
    }
}
