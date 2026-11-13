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
    public init(repository: any GroupsRepository, contacts: any ContactsRepository, account: String, state: GroupsState = GroupsState(), emit: @escaping (GroupsEvent) -> Void) { self.repository = repository; self.contacts = contacts; self.account = account; var initial = state; initial.accountID = account; self.state = initial; self.emit = emit }
    public func send(_ action: GroupsAction) {
        switch action {
        case .openMessages(let group):
            guard let row = state.groups.first(where: { $0.id == group }) else { return }
            navigation?.cancel(); let current = epoch
            navigation = Task { [weak self, repository, account] in
                let result = await repository.conversation(account: account, group: group)
                guard !Task.isCancelled, let self, self.epoch == current else { return }
                switch result { case .success(let conversation): self.emit(.navigate(.groupConversation(conversation, title: row.name))); case .failure(let failure): self.state.failure = failure }
            }
        case .appeared, .refresh: refresh(); observe()
        case .filter(let query): state.query = String(query.prefix(256)); projectRows()
        case .name(let value): if value.utf8.count <= 512 { state.name = value }
        case .mode(let mode):
            guard !state.busy else { return }
            switch mode {
            case .detail(let id), .members(let id), .requests(let id), .created(let id): guard state.groups.contains(where: { $0.id == id }) else { return }
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
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); navigation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
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
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false; self.state.pending = pending; self.state.confirmation = nil
            switch result {
            case .success(let outcome):
                self.state.outcome = outcome; self.emit(.mutationAcknowledged(outcome.groupID))
                if case .create = attempt.mutation { self.state.mode = .created(outcome.groupID) }
                if case .invitation = attempt.mutation { self.state.mode = .list }
                self.refresh()
            case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.authorityFresh = false; self.state.detail = nil; self.state.mode = .accessChanged }
            }
        }
    }
    private func refresh() {
        guard !state.busy else { pendingRefresh = true; return }
        state.accountID = account; readID &+= 1; let id = readID, mode = state.mode; read?.cancel(); state.loading = true; state.authorityFresh = false; state.confirmation = nil; projectRows()
        let selected: String? = switch mode { case .detail(let id), .members(let id), .requests(let id), .created(let id): id; default: nil }
        read = Task { [weak self, repository, contacts, account] in
            let pending = await repository.pending(account: account)
            let groups = await repository.list(account: account), invitations = await repository.invitations(account: account)
            let detail: RepositoryResult<GroupDetail>? = if let selected { await repository.detail(account: account, group: selected) } else { nil }
            let requests: RepositoryResult<[GroupRequestRecord]>? = if let selected { await repository.requests(account: account, group: selected) } else { nil }
            let people: RepositoryResult<[ContactRecord]>? = if case .members = mode { await contacts.contacts(account: account) } else { nil }
            guard !Task.isCancelled, let self, self.readID == id else { return }
            self.state.loading = false; self.state.pending = pending
            switch groups { case .success(let rows): self.state.groups = rows; case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.groups = [] } }
            switch invitations { case .success(let rows): self.state.invitations = rows; case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.invitations = [] } }
            if let detail { switch detail { case .success(let value): self.state.detail = value; self.state.authorityFresh = true
                case .failure(let failure): self.state.detail = nil; self.state.failure = failure; if failure == .locked { self.state.mode = .accessChanged } } }
            if let requests { switch requests { case .success(let rows): self.state.requests = rows; case .failure(let failure): self.state.failure = failure; self.state.requests = [] } }
            if let people { switch people { case .success(let rows): self.state.contacts = rows; case .failure(let failure): self.state.contacts = []; self.state.failure = failure } }
            self.projectRows()
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func projectRows() {
        state.visibleGroups = state.groups.filter { state.query.isEmpty || ($0.name ?? $0.id).localizedCaseInsensitiveContains(state.query) }
        state.eligibleContacts = state.contacts.filter { $0.rootCommitment?.isEmpty == false }
        state.memberRows = state.detail.map { detail in detail.roster.map { member in
            GroupMemberRow(member: member, canManage: state.canManage && member.isActive && member.root != nil && member.role != "owner" && !(member.root == detail.ownRoot && member.device == detail.ownDevice))
        } } ?? []
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
    public func settle() async { await mutation?.value; await navigation?.value; while true { let id = readID; await read?.value; if id == readID { return } } }
    deinit { read?.cancel(); mutation?.cancel(); navigation?.cancel(); observer?.cancel() }
}
