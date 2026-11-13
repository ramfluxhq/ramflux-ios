// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct PendingContactDecision: Equatable, Sendable, Identifiable {
    public let request: ContactRequestRecord
    public let action: ContactDecision
    public var id: String { request.id + action.rawValue }
    public init(request: ContactRequestRecord, action: ContactDecision) { self.request = request; self.action = action }
}
