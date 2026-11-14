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
public struct ChatState: Equatable, Sendable {
    public var isGroup = false
    public var displayTitle = ""
    public var conversationID = ""
    public var messages: [MessageRecord] = []
    public var draft = ""
    public var loading = false
    public var sending = false
    public var failure: AppFailure?
    public var pendingSend: FrozenSend?
    public var pendingDelete: PendingMessageDelete?
    public var composer: ComposerIntent?
    public var reactionTarget: String?
    public var reactionRemove = false
    public var held: HeldMutation?
    public var lastSubmission: SendOutcome?
    public init(messages: [MessageRecord] = [], loading: Bool = false, failure: AppFailure? = nil) { self.messages = messages; self.loading = loading; self.failure = failure }
}
