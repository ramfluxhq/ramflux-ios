// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
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
