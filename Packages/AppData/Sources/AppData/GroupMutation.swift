// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum GroupMutation: Equatable, Sendable {
    case create(id: String, name: String)
    case rename(group: String, epoch: UInt64, name: String)
    case role(group: String, epoch: UInt64, member: GroupMemberRecord, role: String)
    case remove(group: String, epoch: UInt64, member: GroupMemberRecord)
    case add(group: String, epoch: UInt64, principal: String, root: String)
    case invitation(GroupInvitation, accept: Bool)
    public var groupID: String { switch self { case .create(let id, _): id; case .rename(let group, _, _), .role(let group, _, _, _), .remove(let group, _, _), .add(let group, _, _, _): group; case .invitation(let invitation, _): invitation.id } }
}
