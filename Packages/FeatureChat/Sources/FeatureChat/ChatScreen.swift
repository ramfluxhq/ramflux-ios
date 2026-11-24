// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization
#if canImport(UIKit)
import UIKit
#endif
public struct ChatScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: ChatState
    public let onAction: (ChatAction) -> Void
    public init(state: ChatState, onAction: @escaping (ChatAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitChatHeader(state.displayTitle, subtitle: nil, onBack: { dismiss() }, onCall: { onAction(.callRequested) }, onMore: { onAction(.detailsRequested) }, aiMarker: state.peerIsAgent, tag: state.conversationID) {
                KitAvatar(String(state.displayTitle.prefix(1)), size: 36, kind: state.isGroup ? .channel : .person, tag: state.conversationID + "-avatar")
            }
            if state.offline {
                KitTipBar(FeatureChatStrings.text("chat.offline.banner", locale: locale), icon: "wifi-off").padding(.horizontal, KitMetrics.gutter).padding(.top, theme.gap)
            }
            if state.loading && state.messages.isEmpty { ProgressView(FeatureChatStrings.text("chat.loading", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)).padding(.horizontal, KitMetrics.gutter).frame(maxWidth: .infinity, alignment: .leading) }
            if state.messages.isEmpty && state.outbox.isEmpty && !state.loading { RFUnavailableView(title: FeatureChatStrings.text("chat.empty.title", locale: locale), message: FeatureChatStrings.text("chat.empty.message", locale: locale)) }
            ZStack(alignment: .bottom) {
                #if os(iOS)
                ChatTimeline(messages: state.messages, outbox: state.outbox, isGroup: state.isGroup, unreadAnchorID: state.unreadAnchorID, olderAvailable: state.olderAvailable, loadingOlder: state.loadingOlder, media: state.media, revealed: state.revealed, cards: state.cards, agentAuthors: state.agentAuthors, onAction: onAction)
                #else
                ScrollView { LazyVStack { ForEach(TimelineProjection.items(state.messages, outbox: state.outbox, calendar: .current, unreadAnchorID: state.unreadAnchorID, loadingOlder: state.loadingOlder, media: state.media, revealed: state.revealed, cards: state.cards, agentAuthors: state.agentAuthors), id: \.id) { TimelineRow(item: $0, isGroup: state.isGroup, onAction: onAction) } } }
                #endif
                if state.detached {
                    Button(FeatureChatStrings.text("chat.timeline.jumpToLatest", locale: locale)) { onAction(.jumpToLatest) }
                        .rfFont(.caption).padding(theme.gap).background(theme.surface, in: Capsule()).padding(theme.gap)
                }
            }
            if state.peerTyping { Text(FeatureChatStrings.text("chat.typing", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, KitMetrics.gutter) }
            if state.staging { ProgressView(FeatureChatStrings.text("chat.media.preparing", locale: locale)).rfFont(.caption).padding(.horizontal, KitMetrics.gutter) }
            if state.held != nil && !state.sending { Button(FeatureChatStrings.text("chat.send.retry", locale: locale)) { onAction(.retrySameSend) } }
            KitComposer(
                value: draft,
                placeholder: FeatureChatStrings.text("chat.composer.placeholder", locale: locale),
                onSend: { if composerEnabled { onAction(.send) } },
                onAttach: { onAction(.attachRequested) },
                sendActive: composerEnabled && !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                attachEnabled: !state.staging,
                replyAuthor: replyAuthor,
                replyExcerpt: replyExcerpt,
                onCloseReply: state.held == nil && state.composer != nil ? { onAction(.cancelComposer) } : nil,
                tag: "chat-composer"
            )
        } }.privacySensitive()
            .overlay { if let target = actionMessage { ChatActionsOverlay(message: target, onAction: onAction) } }
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
                RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(FeatureChatStrings.text("chat.reaction.title", locale: locale)).rfFont(.page)
                    Button(FeatureChatStrings.text(state.reactionRemove ? "chat.reaction.remove" : "chat.reaction.add", locale: locale)) { onAction(.reactionMode(!state.reactionRemove)) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: KitMetrics.reactionCell))], spacing: theme.gap) {
                        ForEach(ChatReactionPalette.extended, id: \.self) { token in
                            Button(token) { onAction(state.reactionRemove ? .removeReaction(token) : .chooseReaction(token)) }.rfFont(.page)
                        }
                    }
                    Button(FeatureChatStrings.text("chat.composer.cancel", locale: locale)) { onAction(.cancelReaction) }
                }.padding(theme.gap) } }
            }
            .sheet(isPresented: Binding(get: { state.textSelectionTarget != nil }, set: { if !$0 { onAction(.closeTextSelection) } })) {
                if let id = state.textSelectionTarget, let message = state.messages.first(where: { $0.id == id }), case .text(let text) = message.kind {
                    VStack(spacing: 0) {
                        KitPageHeader(FeatureChatStrings.text("chat.message.selectText", locale: locale), onBack: { onAction(.closeTextSelection) }, tag: "chat-select-text-header")
                        ScrollView { KitMessageText(text).padding(KitMetrics.gutter).accessibilityIdentifier("chat-select-text") }
                    }
                    .background(theme.nav.ignoresSafeArea())
                }
            }
            .modifier(ChatMediaSheets(state: state, onAction: onAction))
            .sheet(isPresented: Binding(get: { state.details != nil }, set: { if !$0 { onAction(.closeDetails) } })) {
                if let details = state.details { ChatDetailsSheet(state: details, title: state.displayTitle, conversationID: state.conversationID, isGroup: state.isGroup, onAction: onAction) }
            }
    }
    private var actionMessage: MessageRecord? { state.actionTarget.flatMap { id in state.messages.first { $0.id == id } } }
    private var composerEnabled: Bool { !state.sending && state.held == nil }
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

/// The message action layer (MOB-B03): a dimmed backdrop, the reaction bar and the action menu
/// with the actions the SDK supports for this message.
struct ChatActionsOverlay: View {
    let message: MessageRecord
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            theme.scrim.ignoresSafeArea().onTapGesture { onAction(.closeActions) }
                .accessibilityLabel(Text(FeatureChatStrings.text("chat.composer.cancel", locale: locale)))
                .accessibilityAddTraits(.isButton)
            VStack(alignment: message.isOwn == true ? .trailing : .leading, spacing: theme.gap) {
                KitReactionBar(reactions: ChatReactionPalette.tokens, onReaction: { index in onAction(.chooseReaction(ChatReactionPalette.tokens[index])) }, onMore: { onAction(.beginReact(message.id)) }, tag: "chat-reactions")
                KitContextMenu(entries: entries.map(\.entry), onSelect: { index in entries[index].run() }, tag: "chat-actions")
            }
            .padding(KitMetrics.gutter)
            .frame(maxWidth: .infinity, alignment: message.isOwn == true ? .trailing : .leading)
        }
    }
    private struct Entry { let entry: KitMenuEntry; let run: () -> Void }
    private var entries: [Entry] {
        var list = [Entry(entry: KitMenuEntry(label: FeatureChatStrings.text("common.action.reply", locale: locale), icon: "reply"), run: { onAction(.beginReply(message.id)) })]
        if case .text(let text) = message.kind, !text.isEmpty {
            list.append(Entry(entry: KitMenuEntry(label: FeatureChatStrings.text("chat.message.copy", locale: locale), icon: "copy"), run: {
                #if canImport(UIKit)
                UIPasteboard.general.string = text
                #endif
                onAction(.closeActions)
            }))
            list.append(Entry(entry: KitMenuEntry(label: FeatureChatStrings.text("chat.message.selectText", locale: locale), icon: "type"), run: { onAction(.selectText(message.id)) }))
            if message.isOwn == true {
                list.append(Entry(entry: KitMenuEntry(label: FeatureChatStrings.text("chat.message.edit", locale: locale), icon: "pencil"), run: { onAction(.beginEdit(message.id)) }))
            }
        }
        if message.kind != .deleted, !message.attachments.isEmpty || { if case .text(let text) = message.kind { !text.isEmpty } else { false } }() {
            list.append(Entry(entry: KitMenuEntry(label: FeatureChatStrings.text("chat.message.forward", locale: locale), icon: "forward"), run: { onAction(.forwardRequested(message.id)) }))
        }
        list.append(Entry(entry: KitMenuEntry(label: FeatureChatStrings.text("chat.message.deleteMine", locale: locale), icon: "trash-2", danger: true, groupBefore: true), run: { onAction(.requestDelete(message.id, .local)) }))
        if message.isOwn == true {
            list.append(Entry(entry: KitMenuEntry(label: FeatureChatStrings.text("chat.delete.everyone", locale: locale), icon: "trash-2", danger: true), run: { onAction(.requestDelete(message.id, .everyone)) }))
        }
        return list
    }
}

/// The media presentations of the chat: attach sheet, send preview, album, gallery, viewer,
/// Quick Look, share sheet and camera. Each sheet that can open media carries its own viewer.
struct ChatMediaSheets: ViewModifier {
    let state: ChatState
    let onAction: (ChatAction) -> Void
    func body(content: Content) -> some View {
        content
        .sheet(isPresented: Binding(get: { state.attachSheet }, set: { if !$0 { onAction(.closeAttach) } })) { AttachSheet(onAction: onAction) }
        .sheet(isPresented: Binding(get: { state.preview?.kind == .file && state.gallery == nil }, set: { if !$0 { onAction(.closePreview) } })) {
            #if os(iOS)
            if let preview = state.preview { QuickLookPreview(file: preview.file).ignoresSafeArea() }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: Binding(get: { state.mediaDraft != nil }, set: { if !$0 { onAction(.cancelMediaDraft) } })) {
            if let draft = state.mediaDraft { MediaDraftSheet(draft: draft, onAction: onAction) }
        }
        .sheet(isPresented: Binding(get: { state.album != nil }, set: { if !$0 { onAction(.closeAlbum) } })) {
            if let id = state.album, let message = state.messages.first(where: { $0.id == id }) {
                MediaAlbumSheet(items: message.attachments.filter { $0.kind != .file }, states: state.media, revealed: state.revealed, onAction: onAction)
                    .fullScreenCover(isPresented: Binding(get: { state.preview?.isFullScreen == true }, set: { if !$0 { onAction(.closePreview) } })) {
                        if let preview = state.preview { MediaViewer(preview: preview, saved: state.photoSaved, shareFile: state.shareFile, onAction: onAction) }
                    }
            }
        }
        .sheet(isPresented: Binding(get: { state.gallery != nil }, set: { if !$0 { onAction(.closeGallery) } })) {
            if let gallery = state.gallery {
                ChatGallerySheet(gallery: gallery, states: state.media, revealed: state.revealed, onAction: onAction)
                    .fullScreenCover(isPresented: Binding(get: { state.preview?.isFullScreen == true }, set: { if !$0 { onAction(.closePreview) } })) {
                        if let preview = state.preview { MediaViewer(preview: preview, saved: state.photoSaved, shareFile: state.shareFile, onAction: onAction) }
                    }
                    .sheet(isPresented: Binding(get: { state.preview?.kind == .file }, set: { if !$0 { onAction(.closePreview) } })) {
                        if let preview = state.preview { QuickLookPreview(file: preview.file).ignoresSafeArea() }
                    }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { state.preview?.isFullScreen == true && state.album == nil && state.gallery == nil }, set: { if !$0 { onAction(.closePreview) } })) {
            if let preview = state.preview { MediaViewer(preview: preview, saved: state.photoSaved, shareFile: state.shareFile, onAction: onAction) }
        }
        .fullScreenCover(isPresented: Binding(get: { state.cameraActive }, set: { if !$0 { onAction(.permissionResolved(.camera, granted: false)) } })) { CameraCapture(onAction: onAction).ignoresSafeArea() }
        #endif
    }
}
