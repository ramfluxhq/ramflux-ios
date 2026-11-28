// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import AppData
import FeatureCards
import RFDesign

public struct ChatTimeline: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let isGroup: Bool
    public let onAction: (ChatAction) -> Void
    public let messages: [MessageRecord]
    public let outbox: [OutboxEntry]
    public let unreadAnchorID: String?
    public let olderAvailable: Bool
    public let loadingOlder: Bool
    public let media: [String: MediaTransferState]
    public let revealed: Set<String>
    let cards: [String: CardMessageState]
    let agentAuthors: Set<String>
    let service: [ServiceLine]
    let mls: [MlsTimelineEntry]?
    /// M3: "Show" on the undecryptable banner scrolls to the placeholder row (the serial changes, the id is the row's).
    let mlsScroll: (serial: Int, id: String)?
    public init(messages: [MessageRecord], outbox: [OutboxEntry] = [], isGroup: Bool = false, unreadAnchorID: String? = nil, olderAvailable: Bool = false, loadingOlder: Bool = false, media: [String: MediaTransferState] = [:], revealed: Set<String> = [], cards: [String: CardMessageState] = [:], agentAuthors: Set<String> = [], service: [ServiceLine] = [], mls: [MlsTimelineEntry]? = nil, mlsScroll: (serial: Int, id: String)? = nil, onAction: @escaping (ChatAction) -> Void = { _ in }) {
        self.agentAuthors = agentAuthors; self.service = service; self.mls = mls; self.mlsScroll = mlsScroll
        self.media = media; self.revealed = revealed; self.cards = cards
        self.isGroup = isGroup; self.messages = messages; self.outbox = outbox; self.unreadAnchorID = unreadAnchorID; self.olderAvailable = olderAvailable; self.loadingOlder = loadingOlder; self.onAction = onAction
    }
    public func makeUIViewController(context: Context) -> TimelineController { TimelineController() }
    public func updateUIViewController(_ controller: TimelineController, context: Context) {
        controller.onAction = onAction
        controller.update(messages, outbox: outbox, theme: theme, locale: locale, isGroup: isGroup, unreadAnchorID: unreadAnchorID, olderAvailable: olderAvailable, loadingOlder: loadingOlder, media: media, revealed: revealed, cards: cards, agentAuthors: agentAuthors, service: service, mls: mls)
        if let mlsScroll { controller.scroll(toSerial: mlsScroll.serial, id: mlsScroll.id) }
    }
}
#endif
