// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Delivers the bodies of `message.transient` frames (lossy Typing updates, sequence zero, no
/// replay) for one account. The shared event source owned by the app provides it; until it is
/// connected the chat shows no typing indicator.
public protocol ChatTransientSource: Sendable {
    func transients(account: String) async -> AsyncStream<JSONValue>
}

/// A peer device started or stopped typing in a conversation.
public struct TypingEvent: Sendable, Equatable, CustomStringConvertible {
    public var description: String { "TypingEvent(<redacted>)" }
    public let conversationID: String
    /// The author's account anchor; matched against message authors, never shown.
    public let author: String
    public let active: Bool
    /// Unix seconds after which an active indicator is dropped even without a stop.
    public let expiresAt: Int64
    public init(conversationID: String, author: String, active: Bool, expiresAt: Int64) { self.conversationID = conversationID; self.author = author; self.active = active; self.expiresAt = expiresAt }

    /// Parses a `MessageUpdate` JSON body as the SDK encodes it for `message.transient`
    /// (`bindings/transient.rs`): identity with conversation and author anchor, content Typing
    /// with `active` and `expires_at`. Protobuf JSON uses camelCase; snake_case is accepted.
    /// Anything else (other content, group identity, missing fields) is ignored.
    public static func parse(_ body: JSONValue) -> TypingEvent? {
        func field(_ value: JSONValue?, _ camel: String, _ snake: String) -> JSONValue? { value?[camel] ?? value?[snake] }
        let identity = body["identity"]
        let content = body["content"] ?? body["state"]?["content"]
        guard let typing = content?["typing"], field(identity, "groupId", "group_id") == nil || field(identity, "groupId", "group_id") == .null,
              let conversation = field(identity, "conversationId", "conversation_id")?.string, !conversation.isEmpty, conversation.utf8.count <= 256,
              let author = field(field(identity, "author", "author"), "accountAnchor", "account_anchor")?.string, !author.isEmpty, author.utf8.count <= 256,
              let expires = MessagePage.unsigned(field(typing, "expiresAt", "expires_at")), expires > 0, expires < 253_402_300_799 else { return nil }
        return TypingEvent(conversationID: conversation, author: author, active: typing["active"] == .bool(true), expiresAt: Int64(expires))
    }
}
