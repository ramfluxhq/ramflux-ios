// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct MessageReaction: Identifiable, Sendable, Equatable {
    public var id: String { token }
    public let token: String
    public let count: Int
    public init(token: String, count: Int) { self.token = token; self.count = count }
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
    public let receipt: String?
    public let edited: Bool
    public let replyTo: String?
    public let replyPreview: String?
    public let reactions: [MessageReaction]
    public init(id: String, sender: String, kind: Kind, isOwn: Bool?, timestamp: Int64? = nil, receipt: String? = nil, attachments: [AttachmentRecord] = [], edited: Bool = false, replyTo: String? = nil, replyPreview: String? = nil, reactions: [MessageReaction] = []) {
        self.id = id; self.sender = sender; self.kind = kind; self.isOwn = isOwn; self.timestamp = timestamp; self.receipt = receipt; self.attachments = attachments
        self.edited = edited; self.replyTo = replyTo; self.replyPreview = replyPreview; self.reactions = reactions
    }
}
