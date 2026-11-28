// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
import FeatureChat
@Observable @MainActor public final class ContactsViewModel {
    public private(set) var state: ContactsState
    private let repository: any ContactsRepository
    private let identityRepository: any ContactIdentityRepository
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
    @ObservationIgnored private var lookup: Task<Void, Never>?
    @ObservationIgnored private var lookupTicket: UInt64 = 0
    /// The observation delivered its first update; `settle()` waits for it so the reload it causes is included.
    @ObservationIgnored private var live = false
    @ObservationIgnored private var liveWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var contactWindow = RowWindow<ContactRecord>()
    @ObservationIgnored private var requestWindow = RowWindow<ContactRequestRecord>()
    /// The identity review of the profile contact (the one place a changed identity is accepted from this screen).
    @ObservationIgnored private var review: (contact: String, review: IdentityReview)?
    public init(repository: any ContactsRepository, identity: any ContactIdentityRepository = UnavailableContactIdentityRepository(), account: String, state: ContactsState = ContactsState(), emit: @escaping (ContactsEvent) -> Void) { self.repository = repository; self.identityRepository = identity; self.entryMode = state.mode; self.account = account; self.state = state; self.emit = emit }
    public func send(_ action: ContactsAction) {
        switch action {
        case .appeared: state.mode = entryMode; refresh(); observe()
        case .refresh: refresh(); observe()
        case .loadMore: page(forward: true)
        case .loadBefore: page(forward: false)
        case .filter(let value):
            let query = String(value.prefix(256)); guard query != state.query else { return }
            state.query = query; if state.mode == .contacts { refresh() }
        case .principal(let value):
            // The field is disabled while a send is in flight, so an approved send is never cancelled by typing.
            guard !state.busy else { return }
            let text = String(value.prefix(64 * 1024))
            if text != state.principal { invalidateLookup() }
            state.principal = text
        case .mode(let mode):
            switch mode {
            case .profile(let id): emit(.navigate(.contact(id)))
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
            let principal = state.principal
            if principal.hasPrefix("@") { lookUp(principal); return }
            mutate { [repository, account] in await repository.add(account: account, principal: principal, operationID: UUID().uuidString) }
        case .sendUsername:
            guard !state.busy, !state.unknownMutation, let found = state.usernameLookup, found.text == state.principal else { return }
            let principal = found.text
            mutate { [repository, account] in await repository.add(account: account, principal: principal, operationID: UUID().uuidString) }
        case .requestDecision(let id, let decision):
            let candidates = state.requests + [state.selectedRequest].compactMap { $0 }
            guard !state.busy, !state.unknownMutation, let request = candidates.first(where: { $0.id == id && $0.direction == "inbound" && $0.state == "pending" }) else { return }
            state.pending = PendingContactDecision(request: request, action: decision)
        case .cancelDecision: if !state.busy { state.pending = nil }
        case .confirmDecision:
            guard !state.busy, !state.unknownMutation, let pending = state.pending else { return }
            mutate { [repository, account] in await repository.decide(account: account, request: pending.request.id, decision: pending.action, operationID: UUID().uuidString) }
        case .requestChange(let change):
            guard !state.busy, !state.unknownMutation, let contact = state.selected, Self.allows(change, contact: contact) else { return }
            state.pendingChange = PendingContactChange(contact: contact, change: change)
        case .cancelChange: if !state.busy { state.pendingChange = nil }
        case .confirmChange:
            guard !state.busy, !state.unknownMutation, let pending = state.pendingChange else { return }
            mutate { [repository, account] in await repository.change(account: account, contact: pending.contact, change: pending.change, operationID: UUID().uuidString) }
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .identityReview: review?.review.review()
        case .identityLater: review?.review.later()
        case .identityAccept: review?.review.accept()
        case .disappeared:
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            invalidateLookup(); stopIdentity()
            markLive(); live = false
            let unknown = state.busy || state.unknownMutation; let mode = state.mode
            contactWindow = RowWindow(); requestWindow = RowWindow()
            state = ContactsState(mode: mode); state.unknownMutation = unknown
        }
    }
    /// Which changes the profile screen offers for a contact.
    static func allows(_ change: ContactChange, contact: ContactRecord) -> Bool {
        switch change {
        case .remove: contact.linkID != nil
        case .block: contact.linkID != nil && !contact.blocked
        case .unblock: contact.linkID != nil && contact.blocked
        }
    }
    /// Resolves `@name` before any request is sent. A late answer is dropped unless the field still holds its text.
    private func lookUp(_ text: String) {
        guard let name = UsernameInput.name(text) else { state.failure = .invalidInput; return }
        lookupTicket &+= 1
        let ticket = lookupTicket, current = epoch
        lookup?.cancel()
        state.lookingUp = true; state.failure = nil; state.usernameLookup = nil
        lookup = Task { [weak self, repository, account] in
            let result = await repository.resolveUsername(account: account, name: name)
            guard !Task.isCancelled, let self, self.epoch == current, self.lookupTicket == ticket, self.state.principal == text else { return }
            self.state.lookingUp = false
            switch result {
            case .success(let resolution): self.state.usernameLookup = UsernameLookup(text: text, resolution: resolution)
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    /// Drops a lookup and its answer when the field changes; a late reply for the old text is then ignored.
    private func invalidateLookup() {
        lookupTicket &+= 1; lookup?.cancel(); lookup = nil
        state.lookingUp = false; state.usernameLookup = nil
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
                self.state.usernameLookup = nil
                if self.state.mode == .add { self.state.mode = .contacts }
                if removed { self.emit(.navigate(.contacts)) }
                self.refresh()
            case .failure(let failure): self.state.failure = failure; self.state.unknownMutation = failure == .outcomeUnknown
            }
        }
    }
    private func refresh() {
        readID &+= 1; let current = readID; let mode = state.mode, query = state.query; state.loading = true; state.loadingMore = false; read?.cancel()
        read = Task { [weak self, repository, account] in
            let pendingMutation = await repository.pendingMutation(account: account)
            var failure: AppFailure?
            var contacts: RowWindow<ContactRecord>?, requests: RowWindow<ContactRequestRecord>?
            var selected: ContactRecord?, request: ContactRequestRecord?, card: ContactCardExport?
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
            case .profile(let id):
                switch await repository.contact(account: account, id: id) { case .success(let row): selected = row; case .failure(let error): failure = error }
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
            case .profile:
                if failure == nil { self.state.selected = selected }
                if failure == nil, let selected { self.startIdentity(for: selected) } else { self.stopIdentity() }
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
    /// Follows the profile contact's identity; one review per contact while the profile is shown.
    private func startIdentity(for contact: ContactRecord) {
        if let current = review, current.contact == contact.id { return }
        stopIdentity()
        let created = IdentityReview(repository: identityRepository, account: account, contact: contact.id, name: contact.displayName) { [weak self] panel in self?.state.identity = panel }
        review = (contact.id, created); created.start()
    }
    private func stopIdentity() {
        review?.review.stop(); review = nil; state.identity = IdentityPanel()
    }
    private func stopReading() {
        readID &+= 1; read?.cancel(); state.loading = false; state.loadingMore = false
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let current = watchID; live = false
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch update { case .invalidated: if self.state.loading || self.state.loadingMore { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.state.failure = failure; self.stopReading() }
                self.markLive()
            }
            await observation.stop(); if let self, self.watchID == current { self.observer = nil; self.stopReading(); self.markLive() }
        }
    }
    private func markLive() { live = true; let waiters = liveWaiters; liveWaiters = []; waiters.forEach { $0.resume() } }
    public func settle() async {
        await review?.review.settle()
        if observer != nil && !live { await withCheckedContinuation { liveWaiters.append($0) } }
        await mutation?.value; while true { let current = readID; await read?.value; if current == readID { return } } }
    deinit { read?.cancel(); mutation?.cancel(); observer?.cancel() }
}
