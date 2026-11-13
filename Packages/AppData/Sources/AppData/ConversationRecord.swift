// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct ConversationRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let preview: String
    public let lastActivity: Int64?
    public let unreadCount: UInt?
    public init(id: String, title: String, preview: String, lastActivity: Int64? = nil, unreadCount: UInt? = nil) {
        self.id = id; self.title = title; self.preview = preview; self.lastActivity = lastActivity; self.unreadCount = unreadCount
    }
}
