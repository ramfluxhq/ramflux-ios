// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class GroupsViewModel {
    public private(set) var state: GroupsState
    private let repository: any GroupsRepository
    private let contacts: any ContactsRepository
    private let account: String
    private let emit: (GroupsEvent) -> Void
    @ObservationIgnored private var navigation: Task<Void, Never>?
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var groupWindow = RowWindow<GroupRecord>()
    @ObservationIgnored private var memberWindow = RowWindow<GroupMemberRow>()
    @ObservationIgnored private var contactWindow = RowWindow<ContactRecord>()
    public init(repository: any GroupsRepository, contacts: any ContactsRepository, account: String, state: GroupsState = GroupsState(), emit: @escaping (GroupsEvent) -> Void) { self.repository = repository; self.contacts = contacts; self.account = account; var initial = state; initial.accountID = account; self.state = initial; self.emit = emit }
    public func send(_ action: GroupsAction) {
        switch action {
        case .openMessages(let group):
            guard let row = state.groups.first(where: { $0.id == group }) else { return }
            navigation?.cancel(); let current = epoch
            navigation = Task { [weak self, repository, account] in
                let result = await repository.conversation(account: account, group: group)
                guard !Task.isCancelled, let self, self.epoch == current else { return }
                switch result { case .success(let conversation): self.emit(.navigate(.groupConversation(conversation, group: group, title: row.name))); case .failure(let failure): self.state.failure = failure }
            }
        case .appeared, .refresh: refresh(); observe()
        case .filter(let query):
            let value = String(query.prefix(256)); guard value != state.query else { return }
            state.query = value; reloadGroups()
        case .loadMore: loadMore(contacts: false)
        case .loadMoreContacts: loadMore(contacts: true)
        case .name(let value): if value.utf8.count <= 512 { state.name = value }
        case .mode(let mode):
            guard !state.busy else { return }
            switch mode {
            case .detail(let id), .members(let id), .requests(let id), .created(let id): guard state.groups.contains(where: { $0.id == id }) || state.detail?.group.id == id else { return }
            case .invitation(let id): guard state.invitations.contains(where: { $0.id == id }) else { return }
            default: break
            }
            state.mode = mode; state.outcome = nil; state.confirmation = nil; state.detail = nil; state.name = ""; state.failure = nil; refresh()
        case .prepareCreate:
            guard !state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { state.failure = .invalidInput; return }
            prepare(.create(id: UUID().uuidString, name: state.name))
        case .prepareRename:
            guard state.canManage, let detail = state.detail else { refuseManagement(); return }
            prepare(.rename(group: detail.group.id, epoch: detail.group.epoch, name: state.name))
        case .prepareAdd(let id):
            guard state.canManage, let detail = state.detail, let contact = state.contacts.first(where: { $0.id == id }), let root = contact.rootCommitment else { refuseManagement(); return }
            prepare(.add(group: detail.group.id, epoch: detail.group.epoch, principal: contact.id, root: root))
        case .prepareRole(let id, let role):
            guard state.canManage, let detail = state.detail, let member = detail.roster.first(where: { $0.id == id && $0.isActive && $0.root != nil && $0.role != "owner" }), ["admin","member"].contains(role), !(member.root == detail.ownRoot && member.device == detail.ownDevice) else { refuseManagement(); return }
            prepare(.role(group: detail.group.id, epoch: detail.group.epoch, member: member, role: role))
        case .prepareRemove(let id):
            guard state.canManage, let detail = state.detail, let member = detail.roster.first(where: { $0.id == id && $0.isActive && $0.root != nil && $0.role != "owner" }), !(member.root == detail.ownRoot && member.device == detail.ownDevice) else { refuseManagement(); return }
            prepare(.remove(group: detail.group.id, epoch: detail.group.epoch, member: member))
        case .prepareInvitation(let id, let accept):
            guard let invitation = state.invitations.first(where: { $0.id == id }), invitation.expiresAt > Int64(Date().timeIntervalSince1970) else { state.failure = .invalidInput; return }
            prepare(.invitation(invitation, accept: accept))
        case .prepareLeave:
            guard let detail = state.detail, detail.ownRole != "owner" else { state.failure = repository.unavailable(.ownershipTransfer); return }
            prepare(.leave(group: detail.group.id, epoch: detail.group.epoch))
        case .cancelConfirmation: if !state.busy { state.confirmation = nil }
        case .confirm(let id):
            guard !state.busy, state.pending == nil, let confirmation = state.confirmation, confirmation.id == id else { return }
            dispatch(confirmation.attempt)
        case .reconcileOriginal(let operationID):
            guard !state.busy, let pending = state.pending, pending.operationID == operationID else { return }
            // Reconciliation is an explicit original-key retry, never a fresh mutation.
            dispatch(pending)
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .disappeared:
            EventDiagnostics.note("groups disappeared busy=\(state.busy)"); epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); navigation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            groupWindow = RowWindow(); memberWindow = RowWindow(); contactWindow = RowWindow()
            state = GroupsState()
        }
    }
    private func prepare(_ change: GroupMutation) {
        guard !state.busy, !state.loading, state.pending == nil else { return }
        state.confirmation = GroupConfirmation(attempt: PendingGroupMutation(mutation: change, operationID: UUID().uuidString))
    }
    private func refuseManagement() { state.confirmation = nil; state.mode = .managementUnavailable; state.failure = repository.unavailable(.managementPermission) }
    private func dispatch(_ attempt: PendingGroupMutation) {
        readID &+= 1; read?.cancel(); state.loading = false
        let current = epoch; state.busy = true; state.failure = nil
        mutation = Task { [weak self, repository, account] in
            let result = await repository.mutate(account: account, mutation: attempt.mutation, operationID: attempt.operationID)
            let pending = await repository.pending(account: account)
            EventDiagnostics.note("group mutation result=\(Self.trace(result)) cancelled=\(Task.isCancelled)")
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false; self.state.pending = pending; self.state.confirmation = nil
            switch result {
            case .success(let outcome):
                self.state.outcome = outcome; self.emit(.mutationAcknowledged(outcome.groupID))
                if case .create(_, let name) = attempt.mutation, !outcome.waitingForOwner, !outcome.expired {
                    // The creation reply names the group's conversation: open it without further reads, which
                    // could run before the group list caught up with the new group.
                    if let conversation = outcome.conversationID {
                        EventDiagnostics.note("group create opens the conversation named by the reply")
                        self.emit(.navigate(.groupConversation(conversation, group: outcome.groupID, title: name))); return
                    }
                    let detail = await repository.detail(account: account, group: outcome.groupID)
                    EventDiagnostics.note("group create detail=\(Self.trace(detail)) epoch_kept=\(self.epoch == current)")
                    guard !Task.isCancelled, self.epoch == current else { return }
                    switch detail {
                    case .success(let value):
                        let destination = await repository.conversation(account: account, group: value.group.id)
                        EventDiagnostics.note("group create conversation=\(Self.trace(destination)) epoch_kept=\(self.epoch == current)")
                        guard !Task.isCancelled, self.epoch == current else { return }
                        switch destination {
                        case .success(let conversation): self.emit(.navigate(.groupConversation(conversation, group: value.group.id, title: value.group.name))); return
                        case .failure(let failure): self.state.failure = failure; return
                        }
                    case .failure(let failure): self.state.failure = failure; return
                    }
                }
                if case .invitation = attempt.mutation { self.state.mode = .list }
                if case .leave = attempt.mutation { self.state.mode = .list; self.state.detail = nil }
                self.refresh()
            case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.authorityFresh = false; self.state.detail = nil; self.state.mode = .accessChanged }
            }
        }
    }
    private func refresh() {
        guard !state.busy else { pendingRefresh = true; return }
        state.accountID = account; readID &+= 1; let id = readID, mode = state.mode; read?.cancel(); state.loading = true; state.authorityFresh = false; state.confirmation = nil; projectRows()
        let selected: String? = switch mode { case .detail(let id), .members(let id), .requests(let id), .created(let id): id; default: nil }
        let query = state.query
        read = Task { [weak self, repository, contacts, account] in
            let pending = await repository.pending(account: account)
            let groups = await RowWindow.first({ cursor, limit in await repository.page(account: account, query: query, cursor: cursor, limit: limit) })
            let invitations = await repository.invitations(account: account)
            let detail: RepositoryResult<GroupDetail>? = if let selected { await repository.detail(account: account, group: selected) } else { nil }
            let requests: RepositoryResult<[GroupRequestRecord]>? = if let selected { await repository.requests(account: account, group: selected) } else { nil }
            let people: RepositoryResult<RowWindow<ContactRecord>>? = if case .members = mode { await RowWindow.first({ cursor, limit in await contacts.contactsPage(account: account, query: "", cursor: cursor, limit: limit) }) } else { nil }
            guard !Task.isCancelled, let self, self.readID == id else { return }
            self.state.loading = false; self.state.pending = pending
            switch groups { case .success(let window): self.groupWindow = window; case .failure(let failure): self.state.failure = failure; if failure == .locked { self.groupWindow = RowWindow() } }
            switch invitations {
            case .success(let rows): self.state.invitations = rows; self.state.invitationsFailure = nil
            case .failure(let failure):
                if failure == .locked { self.state.failure = failure; self.state.invitations = [] } else { self.state.invitationsFailure = failure }
            }
            if let detail { switch detail { case .success(let value): self.state.detail = value; self.state.authorityFresh = true
                case .failure(let failure): self.state.detail = nil; self.state.failure = failure; if failure == .locked { self.state.mode = .accessChanged } } }
            if let requests { switch requests { case .success(let rows): self.state.requests = rows; case .failure(let failure): self.state.failure = failure; self.state.requests = [] } }
            if let people { switch people { case .success(let window): self.contactWindow = window; case .failure(let failure): self.contactWindow = RowWindow(); self.state.failure = failure } }
            self.projectRows()
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    /// Re-reads only the group window (a filter change); the detail and the other lists stay.
    private func reloadGroups() {
        guard !state.busy else { return }
        readID &+= 1; let id = readID, query = state.query; read?.cancel(); state.loading = true
        read = Task { [weak self, repository, account] in
            let groups = await RowWindow.first({ cursor, limit in await repository.page(account: account, query: query, cursor: cursor, limit: limit) })
            guard !Task.isCancelled, let self, self.readID == id else { return }
            self.state.loading = false
            switch groups { case .success(let window): self.groupWindow = window; case .failure(let failure): self.state.failure = failure }
            self.projectRows()
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func loadMore(contacts loadContacts: Bool) {
        guard !state.loading, !state.busy else { return }
        let query = state.query, mode = state.mode, groups = groupWindow, people = contactWindow
        switch mode {
        case .list: guard groups.canLoadAfter else { return }
        case .members: guard loadContacts ? people.canLoadAfter : memberWindow.canLoadAfter else { return }
        default: return
        }
        if case .members = mode, !loadContacts { memberWindow = Self.memberWindow(state.detail, canManage: state.canManage, holding: memberWindow.count + memberWindow.pageSize); projectRows(); return }
        readID &+= 1; let id = readID
        read = Task { [weak self, repository, contacts, account] in
            if mode == .list {
                let next = await groups.after { cursor, limit in await repository.page(account: account, query: query, cursor: cursor, limit: limit) }
                guard !Task.isCancelled, let self, self.readID == id else { return }
                switch next { case .success(let window): self.groupWindow = window; case .failure(let failure): if failure == .resyncRequired { self.refresh(); return }; self.state.failure = failure }
            } else {
                let next = await people.after { cursor, limit in await contacts.contactsPage(account: account, query: "", cursor: cursor, limit: limit) }
                guard !Task.isCancelled, let self, self.readID == id else { return }
                switch next { case .success(let window): self.contactWindow = window; case .failure(let failure): if failure == .resyncRequired { self.refresh(); return }; self.state.failure = failure }
            }
            self?.projectRows()
        }
    }
    /// The roster arrives whole in one `group.members` response (the SDK does not page it); the screen
    /// renders a growing window of its projected rows, `holding` rows at most.
    nonisolated static func memberWindow(_ detail: GroupDetail?, canManage: Bool, holding: Int) -> RowWindow<GroupMemberRow> {
        guard let detail else { return RowWindow() }
        let count = min(max(holding, RowWindow<GroupMemberRow>.defaultPageSize), detail.roster.count)
        let rows = detail.roster.prefix(count).map { member in
            GroupMemberRow(member: member, canManage: canManage && member.isActive && member.root != nil && member.role != "owner" && !(member.root == detail.ownRoot && member.device == detail.ownDevice))
        }
        return RowWindow(rows: rows, hasMore: count < detail.roster.count, maxRows: max(count, RowWindow<GroupMemberRow>.defaultMaxRows))
    }
    /// Copies the held windows into the state. The group filter runs in the data layer; only the held
    /// window (at most a few hundred rows) is touched here.
    private func projectRows() {
        state.groups = groupWindow.rows; state.visibleGroups = state.groups; state.canLoadMore = groupWindow.canLoadAfter
        state.contacts = contactWindow.rows; state.eligibleContacts = state.contacts.filter { $0.rootCommitment?.isEmpty == false }; state.canLoadMoreContacts = contactWindow.canLoadAfter
        memberWindow = Self.memberWindow(state.detail, canManage: state.canManage, holding: memberWindow.count)
        state.memberRows = memberWindow.rows; state.canLoadMoreMembers = memberWindow.canLoadAfter
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let id = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch update {
                case .invalidated:
                    self.state.authorityFresh = false; self.state.confirmation = nil; self.projectRows()
                    if self.state.loading { self.pendingRefresh = true } else { self.refresh() }
                case .failed(let failure): self.state.failure = failure; self.state.authorityFresh = false; self.state.confirmation = nil; self.projectRows()
                }
            }
            await observation.stop(); if let self, self.watchID == id { self.observer = nil; self.state.authorityFresh = false }
        }
    }
    nonisolated static func trace<Value>(_ result: RepositoryResult<Value>) -> String {
        switch result { case .success: "success"; case .failure(let failure): "failure(\(failure))" }
    }
    public func settle() async { await mutation?.value; await navigation?.value; while true { let id = readID; await read?.value; if id == readID { return } } }
    deinit { read?.cancel(); mutation?.cancel(); navigation?.cancel(); observer?.cancel() }
}
