// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct AccountRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let isLocked: Bool
    public init(id: String, displayName: String, isLocked: Bool) { self.id = id; self.displayName = displayName; self.isLocked = isLocked }
}
