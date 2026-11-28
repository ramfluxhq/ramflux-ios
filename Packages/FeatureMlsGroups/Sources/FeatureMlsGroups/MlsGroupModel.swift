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
        Task { [session, groupID] in _ = await session.refreshInfo(groupID) }
    }
    public func stop() { observer?.cancel(); observer = nil }
    private func reload() async {
        info = await session.group(groupID)
        invites = await session.inviteSnapshot(groupID)
        members = await session.membersSnapshot(groupID)
        readOnly = await session.isReadOnly(groupID)
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
