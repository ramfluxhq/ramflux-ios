// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class ContactsViewModel {
    public private(set) var state: ContactsState
    private let repository: any ContactsRepository
    private let entryMode: ContactsMode
    private let account: String
    private let emit: (ContactsEvent) -> Void
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    /// The observation delivered its first update; `settle()` waits for it so the reload it causes is included.
    @ObservationIgnored private var live = false
    @ObservationIgnored private var liveWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var contactWindow = RowWindow<ContactRecord>()
    @ObservationIgnored private var requestWindow = RowWindow<ContactRequestRecord>()
    public init(repository: any ContactsRepository, account: String, state: ContactsState = ContactsState(), emit: @escaping (ContactsEvent) -> Void) { self.repository = repository; self.entryMode = state.mode; self.account = account; self.state = state; self.emit = emit }
    public func send(_ action: ContactsAction) {
        switch action {
        case .appeared: state.mode = entryMode; refresh(); observe()
        case .refresh: refresh(); observe()
        case .loadMore: page(forward: true)
        case .loadBefore: page(forward: false)
        case .filter(let value):
            let query = String(value.prefix(256)); guard query != state.query else { return }
            state.query = query; if state.mode == .contacts { refresh() }
        case .principal(let value): state.principal = String(value.prefix(2048))
        case .mode(let mode):
            switch mode {
            case .profile(let id): emit(.navigate(.contact(id)))
            case .safety(let id): emit(.navigate(.safetyNumber(id)))
            default:
                guard mode != state.mode else { return }
                state.mode = mode; state.failure = nil
                if case .request(let id) = mode, let local = state.requests.first(where: { $0.id == id }) { state.selectedRequest = local; return }
                refresh()
            }
        case .retryPendingMutation:
            guard !state.busy, let pending = state.pendingMutation else { return }
            let contact = state.selected
            mutate { [repository, account] in
                switch pending.arguments {
                case .add(let principal): return await repository.add(account: account, principal: principal, operationID: pending.operationID)
                case .decide(let request, let decision): return await repository.decide(account: account, request: request, decision: decision, operationID: pending.operationID)
                case .change(let id, let change):
                    var target = contact?.id == id ? contact : nil
                    if target == nil, case .success(let found) = await repository.contact(account: account, id: id) { target = found }
                    guard let target else { return .failure(.unavailableResource("contacts.unavailable.contactGone")) }
                    return await repository.change(account: account, contact: target, change: change, operationID: pending.operationID)
                }
            }
        case .add:
            guard !state.busy, !state.unknownMutation else { return }
            let principal = state.principal; mutate { [repository, account] in await repository.add(account: account, principal: principal, operationID: UUID().uuidString) }
        case .requestDecision(let id, let decision):
            let candidates = state.requests + [state.selectedRequest].compactMap { $0 }
            guard !state.busy, !state.unknownMutation, let request = candidates.first(where: { $0.id == id && $0.direction == "inbound" && $0.state == "pending" }) else { return }
            state.pending = PendingContactDecision(request: request, action: decision)
        case .cancelDecision: if !state.busy { state.pending = nil }
        case .confirmDecision:
            guard !state.busy, !state.unknownMutation, let pending = state.pending else { return }
            mutate { [repository, account] in await repository.decide(account: account, request: pending.request.id, decision: pending.action, operationID: UUID().uuidString) }
        case .requestChange(let change):
            guard !state.busy, !state.unknownMutation, let contact = state.selected, Self.allows(change, contact: contact, safety: state.safety, stale: state.safetyStale) else { return }
            state.pendingChange = PendingContactChange(contact: contact, change: change)
        case .cancelChange: if !state.busy { state.pendingChange = nil }
        case .confirmChange:
            guard !state.busy, !state.unknownMutation, let pending = state.pendingChange else { return }
            mutate { [repository, account] in await repository.change(account: account, contact: pending.contact, change: pending.change, operationID: UUID().uuidString) }
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .disappeared:
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            markLive(); live = false
            let unknown = state.busy || state.unknownMutation; let mode = state.mode
            contactWindow = RowWindow(); requestWindow = RowWindow()
            state = ContactsState(mode: mode); state.unknownMutation = unknown
        }
    }
    /// Which changes the profile and safety screens offer for a contact.
    static func allows(_ change: ContactChange, contact: ContactRecord, safety: ContactSafety?, stale: Bool) -> Bool {
        switch change {
        case .remove: contact.linkID != nil
        case .block: contact.linkID != nil && !contact.blocked
        case .unblock: contact.linkID != nil && contact.blocked
        case .verify: contact.rootCommitment != nil && !stale && safety.map { !$0.verified && $0.root == contact.rootCommitment } == true
        }
    }
    private func mutate(_ operation: @escaping @Sendable () async -> RepositoryResult<Void>) {
        let current = epoch; state.busy = true; state.failure = nil
        mutation = Task { [weak self, repository, account] in
            let result = await operation()
            let pending = await repository.pendingMutation(account: account)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false; self.state.pendingMutation = pending
            switch result {
            case .success:
                let removed = self.state.pendingChange?.change == .remove
                self.state.unknownMutation = false; self.state.pendingMutation = nil; self.state.pending = nil; self.state.pendingChange = nil; self.state.principal = ""
                if self.state.mode == .add { self.state.mode = .contacts }
                if removed { self.emit(.navigate(.contacts)) }
                self.refresh()
            case .failure(let failure): self.state.failure = failure; self.state.unknownMutation = failure == .outcomeUnknown
            }
        }
    }
    private func refresh() {
        readID &+= 1; let current = readID; let mode = state.mode, query = state.query; state.loading = true; state.loadingMore = false; read?.cancel()
        if case .safety = mode { state.safety = nil; state.safetyPrincipal = nil; state.safetyStale = false }
        read = Task { [weak self, repository, account] in
            let pendingMutation = await repository.pendingMutation(account: account)
            var failure: AppFailure?
            var contacts: RowWindow<ContactRecord>?, requests: RowWindow<ContactRequestRecord>?
            var selected: ContactRecord?, request: ContactRequestRecord?, safety: ContactSafety?, card: ContactCardExport?
            switch mode {
            case .contacts:
                switch await RowWindow.first({ cursor, limit in await repository.contactsPage(account: account, query: query, cursor: cursor, limit: limit) }) {
                case .success(let window): contacts = window; case .failure(let error): failure = error
                }
            case .strangers, .sent:
                let direction = mode == .sent ? "outbound" : "inbound"
                switch await RowWindow.first({ cursor, limit in await repository.requestsPage(account: account, direction: direction, cursor: cursor, limit: limit) }) {
                case .success(let window): requests = window; case .failure(let error): failure = error
                }
            case .request(let id):
                switch await repository.request(account: account, id: id) { case .success(let row): request = row; case .failure(let error): failure = error }
            case .profile(let id), .safety(let id):
                switch await repository.contact(account: account, id: id) { case .success(let row): selected = row; case .failure(let error): failure = error }
                if case .safety = mode, let contact = selected {
                    switch await repository.safety(account: account, contact: contact) {
                    case .success(let value) where value.root == contact.rootCommitment: safety = value
                    case .success: failure = .invalidData
                    case .failure(let error): failure = error
                    }
                }
            case .add: break
            case .myCard:
                switch await repository.ownCard(account: account) { case .success(let value): card = value; case .failure(let error): failure = error }
            }
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false
            self.state.pendingMutation = pendingMutation
            self.state.unknownMutation = pendingMutation != nil
            self.state.failure = failure
            if failure == .locked { self.contactWindow = RowWindow(); self.requestWindow = RowWindow(); self.state.contacts = []; self.state.requests = []; self.state.selected = nil; self.state.selectedRequest = nil }
            if let contacts { self.contactWindow = contacts }
            if let requests { self.requestWindow = requests }
            switch mode {
            case .contacts: self.applyWindow()
            case .strangers, .sent: self.applyWindow()
            case .request: if failure == nil { self.state.selectedRequest = request }
            case .profile: if failure == nil { self.state.selected = selected }
            case .safety(let id):
                self.state.selected = failure == nil ? selected : nil
                self.state.safety = safety; self.state.safetyPrincipal = safety == nil ? nil : id
            case .add: break
            case .myCard: self.state.ownCard = card
            }
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func page(forward: Bool) {
        let mode = state.mode
        guard mode == .contacts || mode == .strangers || mode == .sent, !state.loading, !state.loadingMore else { return }
        let query = state.query, direction = mode == .sent ? "outbound" : "inbound"
        if mode == .contacts { guard forward ? contactWindow.canLoadAfter : contactWindow.canLoadBefore else { return } }
        else { guard forward ? requestWindow.canLoadAfter : requestWindow.canLoadBefore else { return } }
        readID &+= 1; let current = readID; state.loadingMore = true
        let contacts = contactWindow, requests = requestWindow
        read = Task { [weak self, repository, account] in
            var failure: AppFailure?
            var nextContacts: RowWindow<ContactRecord>?, nextRequests: RowWindow<ContactRequestRecord>?
            if mode == .contacts {
                let reader: RowPageReader<ContactRecord> = { cursor, limit in await repository.contactsPage(account: account, query: query, cursor: cursor, limit: limit) }
                switch forward ? await contacts.after(reader) : await contacts.before(reader) { case .success(let window): nextContacts = window; case .failure(let error): failure = error }
            } else {
                let reader: RowPageReader<ContactRequestRecord> = { cursor, limit in await repository.requestsPage(account: account, direction: direction, cursor: cursor, limit: limit) }
                switch forward ? await requests.after(reader) : await requests.before(reader) { case .success(let window): nextRequests = window; case .failure(let error): failure = error }
            }
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loadingMore = false
            if let nextContacts { self.contactWindow = nextContacts }
            if let nextRequests { self.requestWindow = nextRequests }
            self.applyWindow()
            // A snapshot re-read elsewhere invalidates offset cursors: reload the window from the top.
            if failure == .resyncRequired { self.refresh() } else if let failure { self.state.failure = failure }
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func applyWindow() {
        if state.mode == .contacts {
            state.contacts = contactWindow.rows; state.canLoadMore = contactWindow.canLoadAfter; state.canLoadBefore = contactWindow.canLoadBefore
        } else {
            state.requests = requestWindow.rows; state.canLoadMore = requestWindow.canLoadAfter; state.canLoadBefore = requestWindow.canLoadBefore
        }
    }
    private func revokeSafety() {
        readID &+= 1; read?.cancel(); state.loading = false; state.loadingMore = false
        state.safety = nil; state.safetyPrincipal = nil; state.safetyStale = true
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let current = watchID; live = false
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch update { case .invalidated: if self.state.loading || self.state.loadingMore { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.state.failure = failure; self.revokeSafety() }
                self.markLive()
            }
            await observation.stop(); if let self, self.watchID == current { self.observer = nil; self.revokeSafety(); self.markLive() }
        }
    }
    private func markLive() { live = true; let waiters = liveWaiters; liveWaiters = []; waiters.forEach { $0.resume() } }
    public func settle() async {
        if observer != nil && !live { await withCheckedContinuation { liveWaiters.append($0) } }
        await mutation?.value; while true { let current = readID; await read?.value; if current == readID { return } } }
    deinit { read?.cancel(); mutation?.cancel(); observer?.cancel() }
}
