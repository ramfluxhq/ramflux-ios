// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class ConversationsViewModel {
    public private(set) var state: ConversationsState
    private let repository: any ConversationsRepository
    private let account: String
    private let accountTitle: String
    private let emit: (ConversationsEvent) -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var observationID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    /// Screens currently showing this inbox. SwiftUI can deliver a replacement's appearance before the old
    /// instance's disappearance (seen when the scene becomes active again); only the last disappearance may
    /// reset the inbox and stop its observation.
    @ObservationIgnored private var presenters = 0
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var window = ConversationsWindow()
    @ObservationIgnored private var locale = Locale.current
    public init(repository: any ConversationsRepository, account: String, accountTitle: String = "", state: ConversationsState = ConversationsState(), emit: @escaping (ConversationsEvent) -> Void) {
        self.repository = repository
        self.account = account
        self.accountTitle = accountTitle
        var initial = state
        initial.accountID = account
        if initial.accountTitle.isEmpty { initial.accountTitle = accountTitle }
        self.state = initial
        self.emit = emit
    }
    public func send(_ action: ConversationsAction) {
        switch action {
        case .appeared:
            presenters += 1
            EventDiagnostics.note("inbox appeared presenters=\(presenters) observing=\(observer != nil)")
            guard observer == nil else { return }; startObserving()
        case .refresh: if observer == nil { startObserving() } else { reload(search: false) }
        case .loadMore: loadMore()
        case .loadBefore: if window.evictedAbove, state.canLoadBefore, !state.loading, !state.loadingMore { reload(search: false) }
        case .localeChanged(let value): guard value.identifier != locale.identifier else { return }; locale = value; if !state.rows.isEmpty { reload(search: false) }
        case .queryChanged(let query): state.query = String(query.prefix(1024))
        // The field filters the loaded chats by title on the screen; nothing is asked of the account.
        case .search: break
        case .open(let id):
            guard let row = state.rows.first(where: { $0.id == id }) else { return }
            emit(.navigate(row.route))
        case .contacts, .newConversation, .addContact: emit(.navigate(.contacts))
        case .strangers: emit(.navigate(.strangers))
        case .disappeared:
            presenters = max(0, presenters - 1)
            EventDiagnostics.note("inbox disappeared presenters=\(presenters)")
            guard presenters == 0 else { return }
            observationID &+= 1; pendingRefresh = false
            generation &+= 1; work?.cancel(); observer?.cancel(); observer = nil
            window = ConversationsWindow()
            state = ConversationsState()
            state.accountID = account
            state.accountTitle = accountTitle
        }
    }
    /// Starts one observation and its first read. A refresh after a terminal failure restarts it without counting a new presenter.
    private func startObserving() {
        reload(search: false)
        observationID &+= 1; let watchID = observationID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch update { case .invalidated: EventDiagnostics.note("inbox invalidated loading=\(self.state.loading)"); self.state.failure = nil; if self.state.loading || self.state.loadingMore { self.pendingRefresh = true } else { self.reload(search: false) }; case .failed(let failure): self.state.failure = failure }
            }
            await observation.stop()
            if let self, self.observationID == watchID { self.observer = nil }
        }
    }
    private func reload(search: Bool) {
        generation &+= 1; let epoch = generation
        work?.cancel(); state.loading = true; state.loadingMore = false; state.failure = nil
        let query = state.query, pages = min(max(window.pages, 1), ConversationsWindow.refreshPages), locale = locale
        work = Task { [weak self, repository, account] in
            if search {
                let result = await repository.search(account: account, query: query)
                guard !Task.isCancelled, let self, self.generation == epoch else { return }
                self.state.loading = false
                switch result { case .success(let rows): self.state.rows = rows; self.state.canLoadMore = false; self.state.canLoadBefore = false; case .failure(let error): self.state.failure = error }
                return
            }
            async let requests = repository.pendingRequests(account: account)
            let loaded = await Task.detached { await ConversationsWindow.load(repository, account: account, pages: pages, locale: locale, now: Date()) }.value
            let pending = await requests
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            if case .success(let next) = loaded { EventDiagnostics.note("inbox reload rows=\(next.rows.count)") } else { EventDiagnostics.note("inbox reload failed") }
            self.state.loading = false
            if case .success(let count) = pending { self.state.strangersUnread = count }
            switch loaded {
            case .success(let next): self.apply(next)
            case .failure(let error): self.state.failure = error; if error == .locked { self.window = ConversationsWindow(); self.state.rows = []; self.state.canLoadMore = false; self.state.canLoadBefore = false }
            }
            if self.pendingRefresh { self.pendingRefresh = false; self.reload(search: false) }
        }
    }
    private func loadMore() {
        guard window.canLoadMore, state.canLoadMore, !state.loading, !state.loadingMore else { return }
        generation &+= 1; let epoch = generation
        state.loadingMore = true
        let current = window, locale = locale
        work = Task { [weak self, repository, account] in
            let result = await Task.detached { await current.appending(repository, account: account, locale: locale, now: Date()) }.value
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            self.state.loadingMore = false
            switch result { case .success(let next): self.apply(next); case .failure(let error): self.state.failure = error }
            if self.pendingRefresh { self.pendingRefresh = false; self.reload(search: false) }
        }
    }
    private func apply(_ next: ConversationsWindow) {
        window = next; state.rows = next.rows; state.canLoadMore = next.canLoadMore; state.canLoadBefore = next.evictedAbove
    }
    public func joinObservation() async { await observer?.value }
    public func settle() async { while true { let current = generation; await work?.value; if current == generation { return } } }
    deinit { work?.cancel(); observer?.cancel() }
}
