// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// What the conversation details screen shows. Only facts the SDK returns are filled; a missing
/// fact stays nil and the screen shows it as unavailable.
public struct ChatDetails: Sendable, Equatable {
    /// Mute state from `conversation.directory`; nil when the conversation has no directory row.
    public let muted: Bool?
    /// Unix seconds; nil when unmuted or muted without an end.
    public let muteUntil: Int64?
    /// The contact principal whose root commitment equals the direct peer's account anchor.
    /// Nil for groups, for a peer that is not a contact, or before the peer has written.
    public let peerPrincipal: String?
    public let peerName: String?
    public init(muted: Bool?, muteUntil: Int64? = nil, peerPrincipal: String? = nil, peerName: String? = nil) { self.muted = muted; self.muteUntil = muteUntil; self.peerPrincipal = peerPrincipal; self.peerName = peerName }
}
