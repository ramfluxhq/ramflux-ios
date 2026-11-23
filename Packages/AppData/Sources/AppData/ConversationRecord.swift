// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct ConversationRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let preview: String
    public let lastActivity: Int64?
    public let unreadCount: UInt?
    public let timeLabel: String
    public let kind: String
    public let avatarIcon: String
    public let muted: Bool
    public let pinned: Bool
    public let readReceipt: Bool
    public let sender: String
    /// The SDK `group_id` of a group conversation (the two ids can differ for groups created elsewhere).
    public let groupID: String?
    public init(
        id: String,
        title: String,
        preview: String,
        lastActivity: Int64? = nil,
        unreadCount: UInt? = nil,
        timeLabel: String = "",
        kind: String = "person",
        avatarIcon: String = "",
        muted: Bool = false,
        pinned: Bool = false,
        readReceipt: Bool = false,
        sender: String = "",
        groupID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
        self.timeLabel = timeLabel
        self.kind = kind
        self.avatarIcon = avatarIcon
        self.muted = muted
        self.pinned = pinned
        self.readReceipt = readReceipt
        self.sender = sender
        self.groupID = groupID
    }
}
