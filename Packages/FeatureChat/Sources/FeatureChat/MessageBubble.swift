// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct MessageBubble: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let isGroup: Bool
    public let message: MessageRecord
    public let onAction: (ChatAction) -> Void
    public init(message: MessageRecord, isGroup: Bool = false, onAction: @escaping (ChatAction) -> Void = { _ in }) { self.isGroup = isGroup; self.message = message; self.onAction = onAction }
    public var body: some View {
        if message.kind == .callHistory { Label(FeatureChatStrings.text("copy.83ceae7197e5", locale: locale), systemImage: "phone").font(theme.captionFont).frame(maxWidth: .infinity).padding(theme.gap) } else {
        HStack {
            if !isGroup && message.isOwn == true { Spacer(minLength: theme.gap * 2) }
            RFMessageBubble(id: message.id, kind: !isGroup && message.isOwn == true ? .own : .peer, sender: message.sender, theme: theme,
                content: { Text(text).textSelection(.enabled) }, quote: { quote }, attachment: {
                    ForEach(message.attachments) { attachment in Button { onAction(.unavailableAttachment) } label: { Label(attachment.name, systemImage: "doc") } }
                }, footer: { footer })
            if isGroup || message.isOwn == false { Spacer(minLength: theme.gap * 2) }
        }.padding(.horizontal, theme.gap).accessibilityElement(children: .combine)
            .contextMenu {
                if message.kind != .deleted && message.kind != .callHistory {
                    Button(FeatureChatStrings.text("copy.c253f451bdd5", locale: locale)) { onAction(.beginReply(message.id)) }
                    Button(FeatureChatStrings.text("copy.01fad993ff61", locale: locale)) { onAction(.beginReact(message.id)) }
                    if message.isOwn == true, case .text = message.kind { Button(FeatureChatStrings.text("copy.464c4ffd019e", locale: locale)) { onAction(.beginEdit(message.id)) } }
                    Button(FeatureChatStrings.text("copy.f67cb7740d52", locale: locale), role: .destructive) { onAction(.requestDelete(message.id, .local)) }
                    if message.isOwn == true { Button(FeatureChatStrings.text("chat.delete.everyone", locale: locale), role: .destructive) { onAction(.requestDelete(message.id, .everyone)) } }
                }
            }
    }
    }
    private var quote: some View {
        Group {
            if let preview = message.replyPreview { Text(preview).font(theme.captionFont).lineLimit(2) }
            else if message.replyTo != nil { Text(FeatureChatStrings.text("chat.reply.quote", locale: locale)).font(theme.captionFont) }
        }
    }
    private var footer: some View {
        Group {
            if message.edited { Text(FeatureChatStrings.text("chat.edited", locale: locale)).font(theme.captionFont) }
            ForEach(message.reactions) { reaction in Text(reaction.token).font(theme.captionFont); Text(String(reaction.count)).font(theme.captionFont) }
            if let timestamp = message.timestamp, (0...253402300799).contains(timestamp) { Text(Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.hour().minute().locale(locale))).font(theme.captionFont) }
            if let receipt = message.receipt { Text(receipt).font(theme.captionFont) }
        }
    }
    private var text: String { switch message.kind { case .text(let text): text; case .deleted: FeatureChatStrings.text("copy.7e94d4b9a46b", locale: locale); case .callHistory: FeatureChatStrings.text("copy.83ceae7197e5", locale: locale); case .unsupported(let reason): reason } }
}
