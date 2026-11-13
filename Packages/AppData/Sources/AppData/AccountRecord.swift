// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum AccountNetworking: String, Sendable, Equatable { case networkingPending = "networking_pending", live }
public struct AccountRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let networking: AccountNetworking?
    public let isLocked: Bool
    public init(id: String, displayName: String, isLocked: Bool, networking: AccountNetworking? = nil) { self.id = id; self.displayName = displayName; self.isLocked = isLocked; self.networking = networking }
}
