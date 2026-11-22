// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct ContactsState: Equatable, Sendable {
    public var mode: ContactsMode
    public var safetyPrincipal: String?
    public var safetyStale = false
    public var pendingMutation: PendingContactMutation?
    /// The held window of accepted contacts matching `query` (contacts mode).
    public var contacts: [ContactRecord] = []
    /// The held window of requests in the direction of the mode (strangers: inbound, sent: outbound).
    public var requests: [ContactRequestRecord] = []
    public var canLoadMore = false
    public var canLoadBefore = false
    /// The contact of the profile or safety screen.
    public var selected: ContactRecord?
    /// The request of the request screen.
    public var selectedRequest: ContactRequestRecord?
    public var query = ""
    public var principal = ""
    public var loading = false
    public var loadingMore = false
    public var busy = false
    public var failure: AppFailure?
    public var safety: ContactSafety?
    public var pending: PendingContactDecision?
    public var pendingChange: PendingContactChange?
    public var unknownMutation = false
    public init(mode: ContactsMode = .contacts) { self.mode = mode }
}
