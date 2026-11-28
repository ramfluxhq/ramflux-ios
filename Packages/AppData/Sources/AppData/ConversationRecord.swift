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
    /// True when no name is known and `title` is a short identifier (left-to-right isolated) instead.
    public let titleIsIdentifier: Bool
    /// SDK-verified kind of a direct conversation's peer; `.aiAgent` shows the AI marker.
    public let classification: PrincipalClassification
    /// The principal id of a direct conversation's peer, when the directory names one; the key of its identity state.
    public let peer: String?
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
        groupID: String? = nil,
        titleIsIdentifier: Bool = false,
        classification: PrincipalClassification = .unknown,
        peer: String? = nil
    ) {
        self.peer = peer
        self.classification = classification
        self.titleIsIdentifier = titleIsIdentifier
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
public extension ConversationRecord {
    /// The route that opens this directory row: a group conversation with its `group_id`, otherwise a
    /// direct one. The inbox and message notifications both open rows through it.
    var route: AppRoute { groupID.map { .groupConversation(id, group: $0, title: title) } ?? .conversation(id) }
}
