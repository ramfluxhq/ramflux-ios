// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ChatScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: ChatState
    public let onAction: (ChatAction) -> Void
    public init(state: ChatState, onAction: @escaping (ChatAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            RFChatHeader(id: state.conversationID, title: state.displayTitle, subtitle: "", kind: state.isGroup ? .channel : .default, theme: theme, leading: { RFAvatar(initial: String(state.displayTitle.prefix(1)), kind: state.isGroup ? .group : .person, theme: theme) }, trailing: { HStack { Button(FeatureChatStrings.text("copy.d6e645b7d2b2", locale: locale), systemImage: "phone") { onAction(.callRequested) }; Button(FeatureChatStrings.text("copy.d47d7cb0e4f8", locale: locale), systemImage: "ellipsis") { onAction(.detailsRequested) } } })
            if state.loading { ProgressView(FeatureChatStrings.text("copy.aa8730bbb4e3", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if state.messages.isEmpty && !state.loading { RFUnavailableView(title: FeatureChatStrings.text("copy.f42e0f66017d", locale: locale), message: FeatureChatStrings.text("copy.3b6e2ca67ca5", locale: locale)) }
            #if os(iOS)
            ChatTimeline(messages: state.messages, isGroup: state.isGroup, onAction: onAction)
            #else
            ScrollView { LazyVStack { ForEach(state.messages) { MessageBubble(message: $0, isGroup: state.isGroup, onAction: onAction) } } }
            #endif
            if let outcome = state.lastSubmission { Text(outcome.state == .submitted ? FeatureChatStrings.text("copy.a8a3813c2900", locale: locale) : FeatureChatStrings.text("copy.b486522010d5", locale: locale)).font(theme.captionFont) }
            if (state.pendingSend != nil || state.held != nil) && !state.sending { Button(FeatureChatStrings.text("copy.87b2e22c1b97", locale: locale)) { onAction(.retrySameSend) } }
            RFComposerShell(id: "chat-composer", theme: theme, mode: { composerMode }, quote: { composerQuote }, attachment: {
                Button(FeatureChatStrings.text("copy.d406ade2958c", locale: locale), systemImage: "paperclip") { onAction(.unavailableAttachment) }
            }, editor: {
                #if os(iOS)
                ChatComposer(text: Binding(get: { state.draft }, set: { onAction(.draftChanged($0)) }), enabled: composerEnabled) { onAction(.send) }.frame(minHeight: theme.composer_min, maxHeight: theme.composer_min * 3)
                #else
                TextField(FeatureChatStrings.text("copy.2f77668a9dfb", locale: locale), text: Binding(get: { state.draft }, set: { onAction(.draftChanged($0)) }))
                Button(FeatureChatStrings.text("copy.f6f4688ff23d", locale: locale)) { onAction(.send) }.disabled(!composerEnabled)
                #endif
            }, actions: { EmptyView() })
        } }.privacySensitive()
            .toolbar { Button(FeatureChatStrings.text("copy.0e9161011702", locale: locale), systemImage: "arrow.clockwise") { onAction(.refresh) } }
            .sheet(isPresented: Binding(get: { state.pendingDelete != nil }, set: { if !$0 { onAction(.cancelDelete) } })) {
                if let pending = state.pendingDelete {
                    let fact = pending.scope == .everyone ? "chat.delete.everyone.fact" : "copy.4ef7d6d3a97d"
                    let summary = pending.scope == .everyone ? "chat.delete.everyone.summary" : "copy.87e7176a7ce7"
                    RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                        Text(FeatureChatStrings.text("copy.a45a93aaa69f", locale: locale)).font(theme.pageFont)
                        Text(FeatureChatStrings.text(fact, locale: locale))
                        Text(pending.messageID).font(theme.captionFont)
                        RFHostConfirmationActions(summary: FeatureChatStrings.text(summary, locale: locale) + " · " + pending.messageID, enabled: true, confirm: { onAction(.confirmDelete) }, cancel: { onAction(.cancelDelete) }).id(pending.messageID + pending.scope.rawValue)
                    }.padding(theme.gap) }
                }
            }
            .sheet(isPresented: Binding(get: { state.reactionTarget != nil }, set: { if !$0 { onAction(.cancelReaction) } })) {
                RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(FeatureChatStrings.text("chat.reaction.title", locale: locale)).font(theme.pageFont)
                    Button(FeatureChatStrings.text(state.reactionRemove ? "chat.reaction.remove" : "chat.reaction.add", locale: locale)) { onAction(.reactionMode(!state.reactionRemove)) }
                    ForEach(ChatReactionPalette.tokens, id: \.self) { token in
                        Button(token) { onAction(state.reactionRemove ? .removeReaction(token) : .chooseReaction(token)) }
                    }
                    Button(FeatureChatStrings.text("chat.composer.cancel", locale: locale)) { onAction(.cancelReaction) }
                }.padding(theme.gap) }
            }
    }
    private var composerEnabled: Bool { !state.loading && !state.sending && state.pendingSend == nil && state.held == nil }
    private var composerMode: some View {
        Group {
            if case .edit = state.composer {
                HStack {
                    Text(FeatureChatStrings.text("chat.edit.banner", locale: locale)).font(theme.captionFont)
                    if state.held == nil { Button(FeatureChatStrings.text("chat.composer.cancel", locale: locale)) { onAction(.cancelComposer) } }
                }
            }
        }
    }
    private var composerQuote: some View {
        Group {
            if case .reply(_, let preview) = state.composer {
                HStack {
                    Text(FeatureChatStrings.text("chat.reply.banner", locale: locale)).font(theme.captionFont)
                    if !preview.isEmpty { Text(preview).font(theme.captionFont).lineLimit(2) }
                    if state.held == nil { Button(FeatureChatStrings.text("chat.composer.cancel", locale: locale)) { onAction(.cancelComposer) } }
                }
            }
        }
    }
}
