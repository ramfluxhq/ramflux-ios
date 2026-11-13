// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct GroupInvitation: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let creator: String
    public let inviter: String
    public let expiresAt: Int64
    public init(id: String, name: String?, creator: String, inviter: String, expiresAt: Int64) { self.id = id; self.name = name; self.creator = creator; self.inviter = inviter; self.expiresAt = expiresAt }
}
