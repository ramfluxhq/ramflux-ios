// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ChatScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: ChatState
    public let onAction: (ChatAction) -> Void
    public init(state: ChatState, onAction: @escaping (ChatAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitChatHeader(state.displayTitle, subtitle: nil, onBack: { dismiss() }, onCall: { onAction(.callRequested) }, onMore: { onAction(.detailsRequested) }, tag: state.conversationID) {
                KitAvatar(String(state.displayTitle.prefix(1)), size: 36, kind: state.isGroup ? .channel : .person, tag: state.conversationID + "-avatar")
            }
            if state.loading { ProgressView(FeatureChatStrings.text("chat.loading", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if state.messages.isEmpty && !state.loading { RFUnavailableView(title: FeatureChatStrings.text("chat.empty.title", locale: locale), message: FeatureChatStrings.text("chat.empty.message", locale: locale)) }
            #if os(iOS)
            ChatTimeline(messages: state.messages, isGroup: state.isGroup, unreadAnchorID: state.unreadAnchorID, onAction: onAction)
            #else
            ScrollView { LazyVStack { ForEach(TimelineProjection.items(state.messages, calendar: .current, unreadAnchorID: state.unreadAnchorID), id: \.id) { TimelineRow(item: $0, isGroup: state.isGroup, onAction: onAction) } } }
            #endif
            if let outcome = state.lastSubmission { Text(outcome.state == .submitted ? FeatureChatStrings.text("chat.send.submitted", locale: locale) : FeatureChatStrings.text("chat.send.failed", locale: locale)).rfFont(.caption) }
            if (state.pendingSend != nil || state.held != nil) && !state.sending { Button(FeatureChatStrings.text("chat.send.retry", locale: locale)) { onAction(.retrySameSend) } }
            KitComposer(
                value: draft,
                placeholder: FeatureChatStrings.text("chat.composer.placeholder", locale: locale),
                onSend: { if composerEnabled { onAction(.send) } },
                onAttach: { onAction(.unavailableAttachment) },
                sendActive: composerEnabled && !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                replyAuthor: replyAuthor,
                replyExcerpt: replyExcerpt,
                onCloseReply: state.held == nil && state.composer != nil ? { onAction(.cancelComposer) } : nil,
                tag: "chat-composer"
            )
        } }.privacySensitive()
            #if os(iOS)
            .navigationBarBackButtonHidden(true)
            #endif
            .toolbar { Button(FeatureChatStrings.text("common.action.refresh", locale: locale), systemImage: "arrow.clockwise") { onAction(.refresh) } }
            .sheet(isPresented: Binding(get: { state.pendingDelete != nil }, set: { if !$0 { onAction(.cancelDelete) } })) {
                if let pending = state.pendingDelete {
                    let fact = pending.scope == .everyone ? "chat.delete.everyone.fact" : "chat.delete.mine.fact"
                    let summary = pending.scope == .everyone ? "chat.delete.everyone.summary" : "chat.delete.mine.summary"
                    RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                        Text(FeatureChatStrings.text("chat.delete.mine.title", locale: locale)).rfFont(.page)
                        Text(FeatureChatStrings.text(fact, locale: locale))
                        KitIdentifierText(pending.messageID)
                        RFHostConfirmationActions(summary: RFSentence.compose(FeatureChatStrings.text("chat.delete.confirmSummary", locale: locale), [.localized(FeatureChatStrings.text(summary, locale: locale)), .identifier(pending.messageID)], locale: locale), enabled: true, confirm: { onAction(.confirmDelete) }, cancel: { onAction(.cancelDelete) }).id(pending.messageID + pending.scope.rawValue)
                    }.padding(theme.gap) }
                }
            }
            .sheet(isPresented: Binding(get: { state.reactionTarget != nil }, set: { if !$0 { onAction(.cancelReaction) } })) {
                RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(FeatureChatStrings.text("chat.reaction.title", locale: locale)).rfFont(.page)
                    Button(FeatureChatStrings.text(state.reactionRemove ? "chat.reaction.remove" : "chat.reaction.add", locale: locale)) { onAction(.reactionMode(!state.reactionRemove)) }
                    ForEach(ChatReactionPalette.tokens, id: \.self) { token in
                        Button(token) { onAction(state.reactionRemove ? .removeReaction(token) : .chooseReaction(token)) }
                    }
                    Button(FeatureChatStrings.text("chat.composer.cancel", locale: locale)) { onAction(.cancelReaction) }
                }.padding(theme.gap) }
            }
    }
    private var composerEnabled: Bool { !state.loading && !state.sending && state.pendingSend == nil && state.held == nil }
    private var draft: Binding<String> {
        Binding(get: { state.draft }, set: { onAction(.draftChanged(Self.boundedDraft($0))) })
    }
    private var replyAuthor: String? {
        switch state.composer {
        case .edit: FeatureChatStrings.text("chat.edit.banner", locale: locale)
        case .reply: FeatureChatStrings.text("chat.reply.banner", locale: locale)
        case nil: nil
        }
    }
    private var replyExcerpt: String? {
        if case .reply(_, let preview) = state.composer, !preview.isEmpty { return preview }
        return nil
    }
    private static func boundedDraft(_ value: String) -> String {
        var value = value
        while value.utf8.count > 65_536, !value.isEmpty { value.removeLast() }
        return value
    }
}
