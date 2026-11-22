// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ComposerIntent: Equatable, Sendable {
    case reply(messageID: String, preview: String)
    case edit(messageID: String, previousDraft: String)
}
public struct PendingMessageDelete: Equatable, Sendable {
    public let messageID: String
    public let scope: MessageDeleteScope
    public init(messageID: String, scope: MessageDeleteScope) { self.messageID = messageID; self.scope = scope }
}
public enum HeldMutation: Equatable, Sendable {
    case revision(operationID: String, messageID: String, text: String, reply: Bool)
    case reaction(operationID: String, messageID: String, token: String, remove: Bool)
    case deletion(operationID: String, messageID: String, scope: MessageDeleteScope)
}
/// The conversation details sheet (members, mute, safety).
public struct ChatDetailsState: Equatable, Sendable {
    public var loading = true
    public var details: ChatDetails?
    public var failure: AppFailure?
    public var muting = false
    public init(loading: Bool = true, details: ChatDetails? = nil, failure: AppFailure? = nil) { self.loading = loading; self.details = details; self.failure = failure }
}
public struct ChatState: Equatable, Sendable {
    public var isGroup = false
    public var displayTitle = ""
    public var conversationID = ""
    /// The bounded window of read-model rows, newest first.
    public var messages: [MessageRecord] = []
    /// Sends the SDK has not admitted yet, oldest first; drawn below the messages.
    public var outbox: [OutboxEntry] = []
    /// The first unread message; the timeline draws the unread divider above it. Nil while the
    /// SDK supplies no read position (the read model has none today).
    public var unreadAnchorID: String?
    /// True while the read model has older history before the window.
    public var olderAvailable = false
    public var loadingOlder = false
    /// True when the window dropped newer rows while paging back; "Jump to latest" reloads.
    public var detached = false
    public var draft = ""
    public var loading = false
    public var sending = false
    /// The last flush could not reach the account service; queued sends wait for it.
    public var offline = false
    public var failure: AppFailure?
    public var pendingDelete: PendingMessageDelete?
    public var composer: ComposerIntent?
    /// The message whose action menu (reactions, reply, copy, edit, delete) is open.
    public var actionTarget: String?
    public var reactionTarget: String?
    public var reactionRemove = false
    public var held: HeldMutation?
    public var details: ChatDetailsState?
    public init(messages: [MessageRecord] = [], loading: Bool = false, failure: AppFailure? = nil) { self.messages = messages; self.loading = loading; self.failure = failure }
}
