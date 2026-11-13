// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ChatScreen: View {
    public let state: ChatState
    public let onAction: (ChatAction) -> Void
    public init(state: ChatState, onAction: @escaping (ChatAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
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
public struct MessageBubble: View {
    @Environment(\.colorScheme) private var scheme
    public let message: MessageRecord
    public let onAction: (ChatAction) -> Void
    public init(message: MessageRecord, onAction: @escaping (ChatAction) -> Void = { _ in }) { self.message = message; self.onAction = onAction }
    public var body: some View {
        HStack {
            if message.isOwn { Spacer(minLength: 32) }
            RFMessageBubble(id: message.id, kind: message.isOwn ? .own : .peer, sender: message.sender, theme: RFTheme.adaptive(scheme),
                content: { Text(text).textSelection(.enabled) }, quote: { EmptyView() }, attachment: {
                    ForEach(message.attachments) { attachment in Button { onAction(.unavailableAttachment) } label: { Label(attachment.name, systemImage: "doc") } }
                }, footer: {
                    if let timestamp = message.timestamp, (0...253402300799).contains(timestamp) { Text(Date(timeIntervalSince1970: TimeInterval(timestamp)), style: .time).font(.caption) }
                    if let receipt = message.receipt { Text(receipt).font(.caption) }
                })
            if !message.isOwn { Spacer(minLength: 32) }
        }.padding(.horizontal).accessibilityElement(children: .combine)
            .contextMenu {
                if message.kind != .deleted {
                    Button("Reply") { onAction(.unavailableRevision) }; Button("React") { onAction(.unavailableRevision) }
                    if message.isOwn { Button("Edit") { onAction(.unavailableRevision) } }
                    Button("Delete from my devices", role: .destructive) { onAction(.requestDelete(message.id)) }
                }
            }
    }
    private var text: String { switch message.kind { case .text(let text): text; case .deleted: "Message deleted"; case .unsupported(let reason): reason } }
}
public struct ChatHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: ChatCoordinator
    public init(coordinator: ChatCoordinator) { self.coordinator = coordinator }
    public var body: some View { ChatScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .navigationTitle(coordinator.viewModel.conversation).onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, value in coordinator.send(value == .active ? .appeared : .conceal) }
    }
}
public enum ChatPreviews {
    public static let states = [ChatState(), ChatState(loading: true), ChatState(failure: .offline), ChatState(messages: [
        MessageRecord(id: "one", sender: "Alex", kind: .text("Let us review this together."), isOwn: false),
        MessageRecord(id: "two", sender: "", kind: .text("I will take a look."), isOwn: true, receipt: "Device: delivered"),
        MessageRecord(id: "three", sender: "", kind: .deleted, isOwn: false),
    ])]
}
#Preview("Chat") { ChatScreen(state: ChatPreviews.states[3], onAction: { _ in }) }
