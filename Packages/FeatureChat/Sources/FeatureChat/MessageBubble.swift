// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

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
    public let onAction: (ChatAction) -> Void
    public init(message: MessageRecord, isGroup: Bool = false, onAction: @escaping (ChatAction) -> Void = { _ in }) { self.isGroup = isGroup; self.message = message; self.onAction = onAction }
    public var body: some View {
        if message.kind == .callHistory {
            Label(FeatureChatStrings.text("chat.message.callHistory", locale: locale), systemImage: "phone").rfFont(.caption).frame(maxWidth: .infinity).padding(theme.gap)
        } else {
            let placement = BubblePlacement(isOwn: own, text: text, uiDirection: layoutDirection)
            VStack(alignment: placement.alignment, spacing: theme.gap / 2) {
                quote
                KitBubble(text, kind: own ? .own : .incoming, time: clock, edited: message.edited ? FeatureChatStrings.text("chat.edited", locale: locale) : nil, sender: isGroup && !own ? message.sender : nil, read: message.receipt != nil, tag: message.id)
                ForEach(message.attachments) { attachment in
                    Button { onAction(.unavailableAttachment) } label: { Label { KitFileName(attachment.name) } icon: { Image(systemName: "doc") } }
                }
                if !message.reactions.isEmpty {
                    HStack(spacing: theme.gap / 2) {
                        ForEach(message.reactions) { reaction in
                            Text(verbatim: reaction.token)
                            Text(reaction.count, format: .number.locale(locale))
                        }
                    }
                    .rfFont(.caption)
                }
                if let receipt = message.receipt { Text(verbatim: RFUntrustedText(receipt, kind: .messageBody).text).rfFont(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: placement.frameAlignment)
            .padding(.horizontal, theme.gap)
            .accessibilityElement(children: .combine)
            .contextMenu {
                if message.kind != .deleted && message.kind != .callHistory {
                    Button(FeatureChatStrings.text("common.action.reply", locale: locale)) { onAction(.beginReply(message.id)) }
                    Button(FeatureChatStrings.text("chat.message.react", locale: locale)) { onAction(.beginReact(message.id)) }
                    if message.isOwn == true, case .text = message.kind { Button(FeatureChatStrings.text("chat.message.edit", locale: locale)) { onAction(.beginEdit(message.id)) } }
                    Button(FeatureChatStrings.text("chat.message.deleteMine", locale: locale), role: .destructive) { onAction(.requestDelete(message.id, .local)) }
                    if message.isOwn == true { Button(FeatureChatStrings.text("chat.delete.everyone", locale: locale), role: .destructive) { onAction(.requestDelete(message.id, .everyone)) } }
                }
            }
        }
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
        case .deleted: FeatureChatStrings.text("chat.message.deleted", locale: locale)
        case .callHistory: FeatureChatStrings.text("chat.message.callHistory", locale: locale)
        case .unsupported(let reason): reason
        }
    }
}

/// One timeline row: a date chip, the unread divider or a message.
struct TimelineRow: View {
    let item: TimelineItem
    let isGroup: Bool
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme

    var body: some View {
        switch item {
        case .day(let start):
            KitDateChip(TimelineProjection.dayLabel(start, locale: locale, calendar: .current))
        case .unread:
            KitUnreadDivider(FeatureChatStrings.text("chat.timeline.unreadDivider", locale: locale))
                .padding(.horizontal, theme.gap)
        case .message(let record):
            MessageBubble(message: record, isGroup: isGroup, onAction: onAction)
        }
    }
}
