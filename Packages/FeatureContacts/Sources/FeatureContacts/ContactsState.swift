// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ContactsMode: Equatable, Sendable { case contacts, strangers, sent, add, request(String), profile(String), safety(String) }
public struct PendingContactDecision: Equatable, Sendable, Identifiable {
    public let request: ContactRequestRecord
    public let action: ContactDecision
    public var id: String { request.id + action.rawValue }
    public init(request: ContactRequestRecord, action: ContactDecision) { self.request = request; self.action = action }
}
public struct ContactsState: Equatable, Sendable {
    public var mode: ContactsMode
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
public enum ContactsAction: Equatable, Sendable {
    case appeared, disappeared, refresh, mode(ContactsMode), filter(String), principal(String), add
    case requestDecision(String, ContactDecision), confirmDecision, cancelDecision, unavailable(ContactUnavailable)
}
public enum ContactsEvent: Equatable, Sendable { case navigate(AppRoute) }
