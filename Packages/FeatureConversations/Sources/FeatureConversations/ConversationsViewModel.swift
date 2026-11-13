// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData
@Observable @MainActor public final class ConversationsViewModel {
    public private(set) var state: ConversationsState
    private let repository: any ConversationsRepository
    private let account: String
    private let emit: (ConversationsEvent) -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var observationID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var generation: UInt64 = 0
    public init(repository: any ConversationsRepository, account: String, state: ConversationsState = ConversationsState(), emit: @escaping (ConversationsEvent) -> Void) { self.repository = repository; self.account = account; var initial = state; initial.accountID = account; self.state = initial; self.emit = emit }
    public func send(_ action: ConversationsAction) {
        switch action {
        case .appeared:
            guard observer == nil else { return }; reload(search: false)
            observationID &+= 1; let watchID = observationID
            observer = Task { [weak self, repository, account] in
                let observation = await repository.observe(account: account)
                for await update in observation.stream {
                    guard !Task.isCancelled, let self else { break }
                    switch update { case .invalidated: self.state.failure = nil; if self.state.loading { self.pendingRefresh = true } else { self.reload(search: false) }; case .failed(let failure): self.state.failure = failure }
                }
                await observation.stop()
                if let self, self.observationID == watchID { self.observer = nil }
            }
        case .refresh: if observer == nil { send(.appeared) } else { reload(search: false) }
        case .queryChanged(let query): state.query = String(query.prefix(1024))
        case .search: reload(search: true)
        case .open(let id): if state.rows.contains(where: { $0.id == id }) { emit(.navigate(.conversation(id))) }
        case .contacts: emit(.navigate(.contacts))
        case .strangers: emit(.navigate(.strangers))
        case .disappeared:
            observationID &+= 1; pendingRefresh = false
            generation &+= 1; work?.cancel(); observer?.cancel(); observer = nil; state = ConversationsState()
        }
    }
    private func reload(search: Bool) {
        generation &+= 1; let epoch = generation
        work?.cancel(); state.loading = true; state.failure = nil
        let query = state.query
        work = Task { [weak self, repository, account] in
            let result = search ? await repository.search(account: account, query: query) : await repository.list(account: account)
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            self.state.loading = false
            switch result { case .success(let rows): self.state.rows = rows; case .failure(let error): self.state.failure = error; if error == .locked { self.state.rows = [] } }
            if self.pendingRefresh { self.pendingRefresh = false; self.reload(search: false) }
        }
    }
    public func joinObservation() async { await observer?.value }
    public func settle() async { while true { let current = generation; await work?.value; if current == generation { return } } }
    deinit { work?.cancel(); observer?.cancel() }
}
