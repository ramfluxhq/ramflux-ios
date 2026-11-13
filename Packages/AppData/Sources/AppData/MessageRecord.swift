// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct MessageRecord: Identifiable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "MessageRecord" }
    public var debugDescription: String { description }
    public enum Kind: Sendable, Equatable { case text(String), deleted, unsupported(String) }
    public let id: String
    public let sender: String
    public let kind: Kind
    public let isOwn: Bool
    public let timestamp: Int64?
    public let attachments: [AttachmentRecord]
    public let receipt: String?
    public init(id: String, sender: String, kind: Kind, isOwn: Bool, timestamp: Int64? = nil, receipt: String? = nil, attachments: [AttachmentRecord] = []) {
        self.id = id; self.sender = sender; self.kind = kind; self.isOwn = isOwn; self.timestamp = timestamp; self.receipt = receipt; self.attachments = attachments
    }
}
