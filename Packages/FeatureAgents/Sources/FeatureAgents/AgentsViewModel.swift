// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class AgentsViewModel {
    public private(set) var state: AgentsState
    private let repository: any AgentsRepository
    private let account: String
    private let emit: (AgentsEvent) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    public init(repository: any AgentsRepository, account: String, state: AgentsState = AgentsState(), emit: @escaping (AgentsEvent) -> Void) { self.repository = repository; self.account = account; self.state = state; self.emit = emit }
    public func send(_ action: AgentsAction) {
        switch action {
        case .appeared, .retry: load()
        case .mode(let mode): state.mode = mode; state.failure = nil; load()
        case .name(let value): state.draft.name = String(value.prefix(256))
        case .goal(let value): state.draft.goal = String(value.prefix(4096))
        case .create:
            guard state.mode == .create, !state.loading, !state.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            generation &+= 1; let id = generation, draft = state.draft; state.loading = true; task?.cancel()
            task = Task { [weak self, repository, account] in
                let result = await repository.create(account: account, draft: draft)
                guard !Task.isCancelled, let self, self.generation == id else { return }; self.state.loading = false
                switch result { case .success: self.state.failure = .invalidData; case .failure(let failure): self.state.failure = failure }
            }
        case .disappeared: generation &+= 1; task?.cancel(); state = AgentsState()
        }
    }
    private func load() {
        generation &+= 1; let id = generation, mode = state.mode; task?.cancel(); state.loading = true
        task = Task { [weak self, repository, account] in
            let result = await repository.availability(account: account, capability: mode)
            guard !Task.isCancelled, let self, self.generation == id else { return }; self.state.loading = false
            switch result { case .success: self.state.failure = .unsupported; case .failure(let failure): self.state.failure = failure }
        }
    }
    public func settle() async { await task?.value }
    deinit { task?.cancel() }
}
