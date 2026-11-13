// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct GroupMemberRow: Equatable, Sendable, Identifiable {
    public let member: GroupMemberRecord
    public let canManage: Bool
    public var id: String { member.id }
    public init(member: GroupMemberRecord, canManage: Bool) { self.member = member; self.canManage = canManage }
}
