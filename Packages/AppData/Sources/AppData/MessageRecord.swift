// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct MessageReaction: Identifiable, Sendable, Equatable {
    public var id: String { token }
    public let token: String
    public let count: Int
    public init(token: String, count: Int) { self.token = token; self.count = count }
}
/// The delivery state of an own message, folded from the read model's per-device `receipts`.
/// The order is the order of progress: a message read on any device counts as read.
public enum MessageDelivery: Int, Sendable, Equatable, Comparable {
    case sent, delivered, read
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
/// One device's receipt for an own message, as the read model reports it.
public struct MessageReceipt: Sendable, Equatable {
    public let device: String
    public let state: MessageDelivery
    public init(device: String, state: MessageDelivery) { self.device = device; self.state = state }
}
/// The display order of the original event: (`hlc_ms`, `hlc_logical`, `device_sequence`).
public struct MessageOrder: Sendable, Equatable, Comparable {
    public let milliseconds: Int64
    public let logical: Int64
    public let sequence: String
    public init(milliseconds: Int64, logical: Int64 = 0, sequence: String = "") { self.milliseconds = milliseconds; self.logical = logical; self.sequence = sequence }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.milliseconds, lhs.logical, lhs.sequence) < (rhs.milliseconds, rhs.logical, rhs.sequence)
    }
}
public struct MessageRecord: Identifiable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "MessageRecord" }
    public var debugDescription: String { description }
    public enum Kind: Sendable, Equatable { case text(String), deleted, callHistory, unsupported(String) }
    public let id: String
    public let sender: String
    public let kind: Kind
    public let isOwn: Bool?
    public let timestamp: Int64?
    public let attachments: [AttachmentRecord]
    /// Folded delivery state of an own message; nil for incoming messages and own messages
    /// without receipts.
    public let delivery: MessageDelivery?
    public let receipts: [MessageReceipt]
    public let edited: Bool
    public let replyTo: String?
    public let replyPreview: String?
    public let reactions: [MessageReaction]
    /// The author's account anchor; used to resolve the peer of a direct conversation.
    public let authorAnchor: String?
    public let order: MessageOrder?
    /// Durable sequence of this row's last change (the change cursor).
    public let journalSequence: UInt64?
    public init(id: String, sender: String, kind: Kind, isOwn: Bool?, timestamp: Int64? = nil, delivery: MessageDelivery? = nil, receipts: [MessageReceipt] = [], attachments: [AttachmentRecord] = [], edited: Bool = false, replyTo: String? = nil, replyPreview: String? = nil, reactions: [MessageReaction] = [], authorAnchor: String? = nil, order: MessageOrder? = nil, journalSequence: UInt64? = nil) {
        self.id = id; self.sender = sender; self.kind = kind; self.isOwn = isOwn; self.timestamp = timestamp; self.delivery = delivery; self.receipts = receipts; self.attachments = attachments
        self.edited = edited; self.replyTo = replyTo; self.replyPreview = replyPreview; self.reactions = reactions
        self.authorAnchor = authorAnchor; self.order = order; self.journalSequence = journalSequence
    }
    /// A copy with the reply preview resolved from another row of the window.
    public func withReplyPreview(_ preview: String?) -> MessageRecord {
        MessageRecord(id: id, sender: sender, kind: kind, isOwn: isOwn, timestamp: timestamp, delivery: delivery, receipts: receipts, attachments: attachments, edited: edited, replyTo: replyTo, replyPreview: preview, reactions: reactions, authorAnchor: authorAnchor, order: order, journalSequence: journalSequence)
    }
}
