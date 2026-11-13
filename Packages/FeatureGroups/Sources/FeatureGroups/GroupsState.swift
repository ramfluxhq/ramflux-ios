// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct GroupsState: Equatable, Sendable {
    public var accountID = ""
    public var mode: GroupsMode = .list
    public var groups: [GroupRecord] = []
    public var visibleGroups: [GroupRecord] = []
    public var invitations: [GroupInvitation] = []
    public var memberRows: [GroupMemberRow] = []
    public var eligibleContacts: [ContactRecord] = []
    public var detail: GroupDetail?
    public var requests: [GroupRequestRecord] = []
    public var contacts: [ContactRecord] = []
    public var query = ""
    public var name = ""
    public var loading = false
    public var busy = false
    public var failure: AppFailure?
    public var pending: PendingGroupMutation?
    public var confirmation: GroupConfirmation?
    public var outcome: GroupMutationOutcome?
    public var authorityFresh = false
    public var canManage: Bool { authorityFresh && detail?.canManage == true }
    public init(mode: GroupsMode = .list) { self.mode = mode }
}
