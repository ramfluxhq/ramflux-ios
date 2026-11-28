// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureCards
import RFDesign
import RFLocalization

/// Where a message bubble sits and how its text runs. The side follows own versus incoming in
/// the UI's direction (own messages on the trailing side); the text direction inside follows the
/// message content, not the UI language.
struct BubblePlacement: Equatable, Sendable {
    enum Side: Equatable, Sendable { case leading, trailing }
    let side: Side
    let textDirection: LayoutDirection

    init(isOwn: Bool, text: String, uiDirection: LayoutDirection) {
        side = isOwn ? .trailing : .leading
        textDirection = KitMessageText.direction(of: text, surrounding: uiDirection)
    }

    var alignment: HorizontalAlignment { side == .trailing ? .trailing : .leading }
    var frameAlignment: Alignment { side == .trailing ? .trailing : .leading }
}

public struct MessageBubble: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.layoutDirection) private var layoutDirection
    public let isGroup: Bool
    public let message: MessageRecord
    let media: MessageMedia
    public let onAction: (ChatAction) -> Void
    public init(message: MessageRecord, isGroup: Bool = false, onAction: @escaping (ChatAction) -> Void = { _ in }) { self.init(message: message, isGroup: isGroup, media: .none, onAction: onAction) }
    init(message: MessageRecord, isGroup: Bool, media: MessageMedia, onAction: @escaping (ChatAction) -> Void) { self.isGroup = isGroup; self.message = message; self.media = media; self.onAction = onAction }
    public var body: some View {
        if message.kind == .callHistory {
            Label(FeatureChatStrings.text("chat.message.callHistory", locale: locale), systemImage: "phone").rfFont(.caption).frame(maxWidth: .infinity).padding(theme.gap)
        } else {
            let placement = BubblePlacement(isOwn: own, text: text, uiDirection: layoutDirection)
            VStack(alignment: placement.alignment, spacing: theme.gap / 2) {
                if media.authorIsAgent { KitAIMarker(tag: message.id + "-ai") }
                quote
                if message.kind != .deleted, !message.attachments.isEmpty {
                    // Photos and videos first with the caption below (media design 4.1); file cards
                    // follow the text, as on MOB-B02.
                    let visual = message.attachments.filter { $0.kind != .file }
                    if visual.count == 1 {
                        MediaAttachmentView(attachment: visual[0], state: media.states[visual[0].id] ?? .idle, revealed: media.revealed.contains(visual[0].id), isOwn: own, time: clock, onAction: onAction)
                    } else if visual.count > 1 {
                        MediaAlbumGrid(messageID: message.id, items: visual, states: media.states, revealed: media.revealed, onAction: onAction)
                    }
                }
                if let card = media.card {
                    SurfaceCardView(card: card, author: message.sender, isAgent: media.authorIsAgent,
                                    onEvent: { key, event in onAction(.cardEvent(surfaceRef: card.surface.surfaceRef, key: key, event: event)) },
                                    onAnswer: { answer in onAction(.cardAnswer(surfaceRef: card.surface.surfaceRef, answer: answer)) },
                                    onResync: { onAction(.cardResync(surfaceRef: card.surface.surfaceRef)) })
                }
                if showsTextBubble && media.card == nil {
                    KitBubble(text, kind: own ? .own : .incoming, time: clock, edited: message.edited ? FeatureChatStrings.text("chat.edited", locale: locale) : nil, sender: isGroup && !own ? message.sender : nil,
                              read: message.delivery == .read, sentOnly: own && (message.delivery ?? .sent) == .sent && message.kind != .deleted, deleted: message.kind == .deleted, tag: message.id)
                }
                if message.kind != .deleted {
                    ForEach(message.attachments.filter { $0.kind == .file }) { attachment in
                        MediaAttachmentView(attachment: attachment, state: media.states[attachment.id] ?? .idle, revealed: media.revealed.contains(attachment.id), isOwn: own, time: clock, onAction: onAction)
                    }
                }
                if !message.reactions.isEmpty {
                    HStack(spacing: theme.gap / 2) {
                        ForEach(message.reactions) { reaction in
                            HStack(spacing: 2) {
                                Text(verbatim: reaction.token)
                                Text(reaction.count, format: .number.locale(locale))
                            }
                            .padding(.horizontal, theme.gap / 2)
                            .background(theme.surface, in: Capsule())
                        }
                    }
                    .rfFont(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: placement.frameAlignment)
            .padding(.horizontal, theme.gap)
            .contentShape(Rectangle())
            // Bubble text is not selectable here: a long press always opens the message actions,
            // whose "Select text" shows the text with system selection.
            .environment(\.kitMessageTextSelectable, false)
            .onLongPressGesture { if actionable { onAction(.openActions(message.id)) } }
            .accessibilityElement(children: .combine)
            // The side as a stable identifier, for UI tests that check own versus incoming placement.
            .accessibilityIdentifier(placement.side == .trailing ? "message-own" : "message-incoming")
            .accessibilityAction(named: Text(FeatureChatStrings.text("chat.message.actions", locale: locale))) { if actionable { onAction(.openActions(message.id)) } }
        }
    }
    private var actionable: Bool { message.kind != .deleted && message.kind != .callHistory }
    /// A message whose only content is attachments shows no empty text bubble.
    private var showsTextBubble: Bool {
        if case .text(let body) = message.kind, body.isEmpty, !message.attachments.isEmpty { return false }
        return true
    }
    @ViewBuilder private var quote: some View {
        if let preview = message.replyPreview {
            KitMessageText(preview, size: theme.size_secondary, color: theme.secondary, lines: 2, fillsWidth: false)
        } else if message.replyTo != nil {
            Text(FeatureChatStrings.text("chat.reply.quote", locale: locale)).rfFont(.caption)
        }
    }
    /// Own messages sit on the trailing side in direct and group conversations alike.
    private var own: Bool { message.isOwn == true }
    private var clock: String? {
        TimelineProjection.date(of: message).map { $0.formatted(.dateTime.hour().minute().locale(locale)) }
    }
    private var text: String {
        switch message.kind {
        case .text(let text): text
        case .deleted: FeatureChatStrings.text(own ? "chat.message.deletedOwn" : "chat.message.deleted", locale: locale)
        case .callHistory: FeatureChatStrings.text("chat.message.callHistory", locale: locale)
        case .unsupported(let reason): reason
        }
    }
}

/// A send the SDK has not admitted: pending with a clock (MOB-B08), or failed with a red border,
/// an alert mark and "Not sent · Retry" (MOB-B05).
struct OutboxBubble: View {
    let entry: OutboxEntry
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        VStack(alignment: .trailing, spacing: theme.gap / 2) {
            if !entry.media.isEmpty { OutboxMediaTiles(entry: entry) }
            if !entry.text.isEmpty || entry.media.isEmpty {
                HStack(alignment: .center, spacing: theme.gap) {
                    if failed { KitIcon(name: "circle-alert", size: KitMetrics.iconInfo, tint: theme.danger).accessibilityHidden(true) }
                    KitBubble(entry.text, kind: .own, time: failed ? nil : FeatureChatStrings.text(entry.state == .sending ? "chat.outbox.sending" : "chat.outbox.pending", locale: locale), pending: !failed, failed: failed, tag: "outbox-" + entry.operationID)
                }
            }
            if case .failed(let failure) = entry.state {
                HStack(spacing: theme.gap) {
                    Text(entry.media.isEmpty ? FeatureChatStrings.text("chat.outbox.failed", locale: locale) : ChatMediaText.sendFailure(failure, locale: locale)).rfFont(.caption).foregroundStyle(theme.danger)
                    if failure != .localStorage {
                        Button(FeatureChatStrings.text("chat.outbox.retry", locale: locale)) { onAction(.retryOutbox(entry.operationID)) }
                            .rfFont(.caption).foregroundStyle(theme.danger).buttonStyle(.plain)
                    }
                    Menu {
                        Text(failure.message(locale: locale))
                        Button(FeatureChatStrings.text("chat.outbox.discard", locale: locale), role: .destructive) { onAction(.discardOutbox(entry.operationID)) }
                    } label: {
                        KitIcon(name: "info", size: KitMetrics.iconInfo, tint: theme.secondary)
                    }
                    .accessibilityLabel(Text(FeatureChatStrings.text("chat.outbox.details", locale: locale)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, theme.gap)
        .accessibilityElement(children: .contain)
    }
    private var failed: Bool { if case .failed = entry.state { true } else { false } }
}

/// The staged items of an unadmitted media send, each with its state: a clock while queued, an
/// indeterminate ring while sending (the SDK reports no upload bytes), an alert when failed.
struct OutboxMediaTiles: View {
    let entry: OutboxEntry
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        HStack(spacing: theme.gap / 2) {
            ForEach(Array(entry.media.prefix(4).enumerated()), id: \.offset) { index, item in
                ZStack {
                    if item.mime.hasPrefix("image/") { PipelineImage(source: .file(item.file), maxPixel: ChatMediaText.tilePixels) } else { theme.surface }
                    if index == 3 && entry.media.count > 4 {
                        Text(verbatim: "+" + (entry.media.count - 3).formatted(.number.locale(locale))).rfFont(.page).foregroundStyle(theme.text)
                    }
                }
                .frame(width: ChatMediaText.tileSide, height: ChatMediaText.tileSide)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius_md))
                .overlay(alignment: .bottomTrailing) { badge.padding(theme.gap / 2) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(FeatureChatStrings.format("chat.outbox.media", entry.media.count, locale: locale)))
    }
    @ViewBuilder private var badge: some View {
        switch entry.state {
        case .queued: KitIcon(name: "clock-3", size: KitMetrics.iconInfo, tint: theme.text).padding(2).background(theme.overlay, in: Circle())
        case .sending: ProgressView().controlSize(.small).padding(2).background(theme.overlay, in: Circle())
        case .failed: KitIcon(name: "circle-alert", size: KitMetrics.iconInfo, tint: theme.danger).padding(2).background(theme.overlay, in: Circle())
        }
    }
}

/// Display text for an attachment's type and size; sizes use the locale's byte formatter.
enum ChatAttachmentText {
    static func meta(_ attachment: AttachmentRecord, locale: Locale) -> String {
        let type = typeLabel(attachment)
        guard let size = attachment.size else { return type }
        let formatted = size.formatted(.byteCount(style: .file).locale(locale))
        return RFSentence.compose(FeatureChatStrings.text("chat.attachment.typeSize", locale: locale), [.identifier(type), .localized(formatted)], locale: locale)
    }
    /// The real extension from the file name (upper case, Latin), else the declared subtype.
    static func typeLabel(_ attachment: AttachmentRecord) -> String {
        let clean = RFUntrustedText.clean(attachment.name)
        if let dot = clean.lastIndex(of: "."), clean.index(after: dot) < clean.endIndex {
            let ext = clean[clean.index(after: dot)...]
            if ext.count <= 8, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return ext.uppercased() }
        }
        return (attachment.mime?.split(separator: "/").last.map(String.init) ?? "").uppercased()
    }
    static func icon(_ attachment: AttachmentRecord) -> String {
        switch attachment.kind {
        case .image, .animated: "images"
        case .video: "video"
        case .file: "file-text"
        }
    }
}

/// One timeline row: the history loader, a date chip, the unread divider, a message or an
/// unadmitted send.
struct TimelineRow: View {
    let item: TimelineItem
    let isGroup: Bool
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme

    var body: some View {
        switch item {
        case .history:
            ProgressView(FeatureChatStrings.text("chat.timeline.loadingOlder", locale: locale)).rfFont(.caption).frame(maxWidth: .infinity).padding(theme.gap)
        case .day(let start):
            KitDateChip(TimelineProjection.dayLabel(start, locale: locale, calendar: .current))
        case .unread:
            KitUnreadDivider(FeatureChatStrings.text("chat.timeline.unreadDivider", locale: locale))
                .padding(.horizontal, theme.gap)
        case .message(let record, let media):
            MessageBubble(message: record, isGroup: isGroup, media: media, onAction: onAction)
        case .outbox(let entry):
            OutboxBubble(entry: entry, onAction: onAction)
        }
    }
}
