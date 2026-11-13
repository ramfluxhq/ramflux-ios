// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum GroupsPreviews {
    public static var states: [GroupsState] {
        let group = GroupRecord(id: "preview-group", name: "Research", epoch: 9, members: ["phone", "peer-phone"])
        let owner = GroupMemberRecord(principal: "preview-account", root: "preview-own-root", device: "phone", role: "owner")
        let peer = GroupMemberRecord(principal: "preview-peer", root: "preview-peer-root", device: "peer-phone", role: "member")
        let detail = GroupDetail(group: group, roster: [owner, peer], ownRoot: "preview-own-root", ownDevice: "phone", authorized: true)
        let invitation = GroupInvitation(id: "preview-invitation", name: "Planning", creator: "preview-creator-root", inviter: "preview-inviter-root", expiresAt: 4_102_444_800)
        var populated = GroupsState(); populated.accountID = "preview-account"; populated.groups = [group]; populated.visibleGroups = [group]; populated.invitations = [invitation]
        var loading = GroupsState(); loading.loading = true
        var offline = populated; offline.failure = .offline
        var error = GroupsState(); error.failure = .invalidData
        let modes: [GroupsMode] = [.create, .detail(group.id), .members(group.id), .created(group.id), .invitation(invitation.id), .requests(group.id), .managementUnavailable, .accessChanged]
        return [GroupsState(), loading, offline, error, populated] + modes.map { mode in
            var state = populated; state.mode = mode; state.detail = detail; state.authorityFresh = true
            state.memberRows = [GroupMemberRow(member: owner, canManage: false), GroupMemberRow(member: peer, canManage: true)]
            state.contacts = [ContactRecord(id: "preview-contact", displayName: "Alex", subtitle: "preview-contact", rootCommitment: "preview-contact-root")]; state.eligibleContacts = state.contacts
            state.requests = [GroupRequestRecord(id: "preview-request", groupID: group.id, status: "waiting_for_owner", waitingForOwner: true, expiresAt: 4_102_444_800)]
            return state
        }
    }
}
#Preview("Groups") { RFThemeScope { GroupsScreen(state: GroupsPreviews.states[4], onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(GroupsPreviews.states.indices, id: \.self) { index in GroupsScreen(state: GroupsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(GroupsPreviews.states.indices, id: \.self) { index in GroupsScreen(state: GroupsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
