// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class ContactsViewModel {
    public private(set) var state: ContactsState
    private let repository: any ContactsRepository
    private let account: String
    private let emit: (ContactsEvent) -> Void
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    public init(repository: any ContactsRepository, account: String, state: ContactsState = ContactsState(), emit: @escaping (ContactsEvent) -> Void) { self.repository = repository; self.account = account; self.state = state; self.emit = emit }
    public func send(_ action: ContactsAction) {
        switch action {
        case .appeared, .refresh: refresh(); observe()
        case .filter(let value): state.query = String(value.prefix(256)); projectVisibleRows()
        case .principal(let value): state.principal = String(value.prefix(2048))
        case .mode(let mode):
            switch mode { case .profile(let id): emit(.navigate(.contact(id))); case .safety(let id): emit(.navigate(.safetyNumber(id))); default: state.mode = mode; state.failure = nil; projectVisibleRows() }
        case .retryPendingMutation:
            guard !state.busy, let pending = state.pendingMutation else { return }
            mutate { [repository, account] in
                switch pending.arguments {
                case .add(let principal): await repository.add(account: account, principal: principal, operationID: pending.operationID)
                case .decide(let request, let decision): await repository.decide(account: account, request: request, decision: decision, operationID: pending.operationID)
                }
            }
        case .add:
            guard !state.busy, !state.unknownMutation else { return }
            let principal = state.principal; mutate { [repository, account] in await repository.add(account: account, principal: principal, operationID: UUID().uuidString) }
        case .requestDecision(let id, let decision):
            guard !state.busy, !state.unknownMutation, let request = state.requests.first(where: { $0.id == id && $0.direction == "inbound" && $0.state == "pending" }) else { return }
            state.pending = PendingContactDecision(request: request, action: decision)
        case .cancelDecision: if !state.busy { state.pending = nil }
        case .confirmDecision:
            guard !state.busy, !state.unknownMutation, let pending = state.pending else { return }
            mutate { [repository, account] in await repository.decide(account: account, request: pending.request.id, decision: pending.action, operationID: UUID().uuidString) }
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .disappeared:
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            let unknown = state.busy || state.unknownMutation; let mode = state.mode
            state = ContactsState(mode: mode); state.unknownMutation = unknown
        }
    }
    private func mutate(_ operation: @escaping @Sendable () async -> RepositoryResult<Void>) {
        let current = epoch; state.busy = true; state.failure = nil
        mutation = Task { [weak self, repository, account] in
            let result = await operation()
            let pending = await repository.pendingMutation(account: account)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false; self.state.pendingMutation = pending
            switch result { case .success: self.state.unknownMutation = false; self.state.pendingMutation = nil; self.state.pending = nil; self.state.principal = ""; if self.state.mode == .add { self.state.mode = .contacts }; self.refresh()
            case .failure(let failure): self.state.failure = failure; self.state.unknownMutation = failure == .outcomeUnknown }
        }
    }
    private func refresh() {
        readID &+= 1; let current = readID; let mode = state.mode; state.loading = true; read?.cancel()
        if case .safety = mode { state.safety = nil; state.safetyPrincipal = nil; state.safetyStale = false }
        read = Task { [weak self, repository, account] in
            let pendingMutation = await repository.pendingMutation(account: account)
            let contacts = await repository.contacts(account: account), requests = await repository.requests(account: account)
            var safety: RepositoryResult<ContactSafety>?
            if case .safety(let id) = mode, case .success(let rows) = contacts, let contact = rows.first(where: { $0.id == id }) { safety = await repository.safety(account: account, contact: contact) }
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false
            self.state.pendingMutation = pendingMutation
            self.state.unknownMutation = pendingMutation != nil
            switch contacts { case .success(let rows): self.state.contacts = rows; case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.contacts = [] } }
            switch requests { case .success(let rows): self.state.requests = rows; case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.requests = [] } }
            if case .safety(let selected) = mode {
                self.state.safety = nil; self.state.safetyPrincipal = nil; self.state.safetyStale = false
                if case .success(let rows) = contacts, let contact = rows.first(where: { $0.id == selected }),
                   case .success(let value) = safety, value.root == contact.rootCommitment {
                    self.state.safety = value; self.state.safetyPrincipal = selected
                } else if case .failure(let failure) = safety { self.state.failure = failure }
            }
            self.projectVisibleRows()
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func revokeSafety() {
        readID &+= 1; read?.cancel(); state.loading = false
        state.safety = nil; state.safetyPrincipal = nil; state.safetyStale = true
    }
    private func projectVisibleRows() {
        state.visibleContacts = state.contacts.filter { state.query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(state.query) || $0.id.localizedCaseInsensitiveContains(state.query) }
        state.visibleRequests = state.requests.filter { $0.direction == (state.mode == .sent ? "outbound" : "inbound") }
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let current = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch update { case .invalidated: if self.state.loading { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.state.failure = failure; self.revokeSafety() }
            }
            await observation.stop(); if let self, self.watchID == current { self.observer = nil; self.revokeSafety() }
        }
    }
    public func settle() async { await mutation?.value; while true { let current = readID; await read?.value; if current == readID { return } } }
    deinit { read?.cancel(); mutation?.cancel(); observer?.cancel() }
}
