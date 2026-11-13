// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct GroupMemberRecord: Equatable, Sendable, Identifiable {
    public let principal: String
    public let root: String?
    public let device: String
    public let role: String
    public let isActive: Bool
    public var id: String { (root ?? "") + "\u{0}" + device }
    public init(principal: String, root: String?, device: String, role: String, isActive: Bool = true) { self.principal = principal; self.root = root; self.device = device; self.role = role; self.isActive = isActive }
}
