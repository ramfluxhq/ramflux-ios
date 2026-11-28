// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData

/// One group's info, invites and members as the screens show them. Reads session snapshots; every intent is one call.
@Observable @MainActor public final class MlsGroupModel {
    public let groupID: String
    public private(set) var info: MlsGroupInfo?
    public private(set) var invites = MlsInviteSnapshot()
    public private(set) var members = MlsMembersSnapshot()
    public private(set) var readOnly: MlsReadOnly?
    /// M3: the admin owner's view of this group (requests, the busy slot, push, warnings).
    public private(set) var admin = MlsAdminSnapshot()
    public private(set) var leaving = false
    public private(set) var leaveError: MlsGroupError?
    public var search = ""
    @ObservationIgnored private let session: MlsGroupSession
    @ObservationIgnored private var observer: Task<Void, Never>?

    public init(session: MlsGroupSession, groupID: String) { self.session = session; self.groupID = groupID }

    public func start() {
        guard observer == nil else { return }
        observer = Task { [weak self] in
            guard let session = self?.session else { return }
            let changes = await session.changes()
            await self?.reload()
            for await _ in changes { await self?.reload() }
        }
        // The requests list loads once when group info opens for an admin of an approval group (a read, never an action).
        Task { [session, groupID] in _ = await session.refreshInfo(groupID); await session.prepareRequests(groupID) }
    }
    public func stop() { observer?.cancel(); observer = nil }
    private func reload() async {
        info = await session.group(groupID)
        invites = await session.inviteSnapshot(groupID)
        members = await session.membersSnapshot(groupID)
        readOnly = await session.isReadOnly(groupID)
        admin = await session.adminSnapshot(groupID)
    }

    // Info
    public func refresh() { Task { [session, groupID] in _ = await session.refreshInfo(groupID); await session.refresh(groupID) } }
    public func leave() {
        guard !leaving else { return }
        leaving = true; leaveError = nil
        Task { [weak self, session, groupID] in
            let result = await session.leave(groupID)
            self?.leaving = false
            if case .failure(let error) = result { self?.leaveError = error }
        }
    }
    public func clearLeaveError() { leaveError = nil }

    // Invites
    public func loadInvites() { Task { [session, groupID] in await session.loadInvites(groupID) } }
    public func createInvite(maxUses: Int, ttlSeconds: Int) { Task { [session, groupID] in await session.createInvite(groupID, maxUses: maxUses, ttlSeconds: ttlSeconds) } }
    public func revoke(_ inviteID: String) { Task { [session, groupID] in await session.revokeInvite(groupID, inviteID: inviteID) } }

    // Members
    public func openMembers() { Task { [session, groupID] in await session.openMembers(groupID) } }
    public func memberAppeared(_ anchor: String) {
        guard let index = members.rows.firstIndex(where: { $0.anchor == anchor }), index >= members.rows.count - 20, members.hasMore, members.phase == .done else { return }
        Task { [session, groupID] in await session.loadMoreMembers(groupID) }
    }
    public func retryMembers() { Task { [session, groupID] in await session.retryMembers(groupID) } }
    public func searchChanged() {
        guard !search.isEmpty, members.hasMore else { return }
        Task { [session, groupID] in await session.loadAllMembers(groupID) }
    }
    /// Rows that match the search among the loaded ones.
    public var filteredMembers: [MlsMemberRow] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return members.rows }
        return members.rows.filter { ($0.display ?? "").localizedCaseInsensitiveContains(query) }
    }
}

// MARK: M3 admin intents (every call is one tap through a confirmation, the name Save, the approval switch or the push picker)
extension MlsGroupModel {
    public var myRole: MlsRole { info?.myRole ?? .member }
    public var isAdmin: Bool { myRole == .owner || myRole == .admin }
    /// The requests entry exists for the owner and admins of an approval group that is not read-only.
    public var showsRequests: Bool { isAdmin && info?.approval == true && readOnly == nil }
    public var showsSettings: Bool { isAdmin && readOnly == nil }
    /// Every commit entry is off while one is in flight or paced; the reason is shown, never retried.
    public func entriesBlocked(now: Date = Date()) -> Bool { admin.busy != nil || (admin.pacedUntil.map { $0 > Int64(now.timeIntervalSince1970 * 1000) } ?? false) }

    public func openRequests() { Task { [session, groupID] in await session.openRequests(groupID) } }
    public func retryRequests() { Task { [session, groupID] in await session.retryRequests(groupID) } }
    /// Pages in when the row is within 20 rows of the end.
    public func requestRowAppeared(index: Int) {
        guard index >= admin.requests.rows.count - 20, admin.requests.more, admin.requests.phase == .loaded else { return }
        Task { [session, groupID] in await session.loadMoreRequests(groupID) }
    }
    public func clearNotice() { Task { [session, groupID] in await session.clearAdminNotice(groupID) } }

    /// The confirmation's primary button: the one place a confirmed admin action reaches the session.
    public func perform(_ confirmation: MlsAdminConfirmation) {
        Task { [session, groupID] in
            switch confirmation.kind {
            case .approve(let id): await session.approve(groupID, requestID: id)
            case .decline(let id): await session.decline(groupID, requestID: id)
            case .makeAdmin(let anchor): await session.setRole(groupID, anchor: anchor, role: .admin)
            case .makeMember(let anchor): await session.setRole(groupID, anchor: anchor, role: .member)
            case .remove(let anchor): await session.removeMember(groupID, anchor: anchor)
            case .ban(let anchor): await session.banMember(groupID, anchor: anchor)
            case .approvalOff: await session.setApproval(groupID, on: false)
            }
        }
    }
    /// The name form's Save: its own confirmation (one call with `{name}` only).
    public func saveName(_ name: String) { Task { [session, groupID] in await session.setName(groupID, name: name) } }
    /// The approval switch turned on needs no confirmation (turning it off goes through `perform`).
    public func turnApprovalOn() { Task { [session, groupID] in await session.setApproval(groupID, on: true) } }
    public func choosePush(_ push: MlsPush) { Task { [session, groupID] in await session.setPush(groupID, push) } }
}
