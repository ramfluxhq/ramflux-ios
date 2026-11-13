// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct GroupDetail: Equatable, Sendable {
    public let group: GroupRecord
    public let roster: [GroupMemberRecord]
    public let ownRoot: String
    public let ownDevice: String
    public let authorized: Bool
    public var ownRole: String? { roster.first(where: { $0.root == ownRoot && $0.device == ownDevice && $0.isActive })?.role }
    public var canManage: Bool { authorized && ownRole.map { ["owner", "admin"].contains($0) } == true }
    public init(group: GroupRecord, roster: [GroupMemberRecord], ownRoot: String, ownDevice: String, authorized: Bool) { self.group = group; self.roster = roster; self.ownRoot = ownRoot; self.ownDevice = ownDevice; self.authorized = authorized }
}
