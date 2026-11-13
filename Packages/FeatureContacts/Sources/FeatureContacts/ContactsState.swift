// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct ContactsState: Equatable, Sendable {
    public var mode: ContactsMode
    public var visibleContacts: [ContactRecord] = []
    public var visibleRequests: [ContactRequestRecord] = []
    public var safetyPrincipal: String?
    public var safetyStale = false
    public var pendingMutation: PendingContactMutation?
    public var contacts: [ContactRecord] = []
    public var requests: [ContactRequestRecord] = []
    public var query = ""
    public var principal = ""
    public var loading = false
    public var busy = false
    public var failure: AppFailure?
    public var safety: ContactSafety?
    public var pending: PendingContactDecision?
    public var unknownMutation = false
    public init(mode: ContactsMode = .contacts) { self.mode = mode }
}
