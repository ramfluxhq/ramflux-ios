// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct PendingContactDecision: Equatable, Sendable, Identifiable {
    public let request: ContactRequestRecord
    public let action: ContactDecision
    public var id: String { request.id + action.rawValue }
    public init(request: ContactRequestRecord, action: ContactDecision) { self.request = request; self.action = action }
}
/// A change to an accepted contact waiting for the host-drawn confirmation.
public struct PendingContactChange: Equatable, Sendable, Identifiable {
    public let contact: ContactRecord
    public let change: ContactChange
    public var id: String { contact.id + change.rawValue }
    public init(contact: ContactRecord, change: ContactChange) { self.contact = contact; self.change = change }
}
