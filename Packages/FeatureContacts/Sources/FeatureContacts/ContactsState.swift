// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
import FeatureChat
public struct ContactsState: Equatable, Sendable {
    public var mode: ContactsMode
    public var pendingMutation: PendingContactMutation?
    /// The held window of accepted contacts matching `query` (contacts mode).
    public var contacts: [ContactRecord] = []
    /// The held window of requests in the direction of the mode (strangers: inbound, sent: outbound).
    public var requests: [ContactRequestRecord] = []
    public var canLoadMore = false
    public var canLoadBefore = false
    /// The contact of the profile screen.
    public var selected: ContactRecord?
    /// The request of the request screen.
    public var selectedRequest: ContactRequestRecord?
    public var query = ""
    public var principal = ""
    public var loading = false
    public var loadingMore = false
    public var busy = false
    public var failure: AppFailure?
    /// The profile contact's identity: the encryption section and the review sheet.
    public var identity = IdentityPanel()
    /// This account's contact card (my-card mode).
    public var ownCard: ContactCardExport?
    public var pending: PendingContactDecision?
    public var pendingChange: PendingContactChange?
    public var unknownMutation = false
    /// The `@name` lookup of the add screen: the field text it was made for and the directory's answer.
    public var usernameLookup: UsernameLookup?
    /// A `@name` lookup is in flight.
    public var lookingUp = false
    public init(mode: ContactsMode = .contacts) { self.mode = mode }
}
/// The answer of a `@name` lookup, kept with the exact field text it resolved, so a request is sent only for that text.
public struct UsernameLookup: Equatable, Sendable {
    public let text: String
    public let resolution: UsernameResolution
    public init(text: String, resolution: UsernameResolution) { self.text = text; self.resolution = resolution }
}
