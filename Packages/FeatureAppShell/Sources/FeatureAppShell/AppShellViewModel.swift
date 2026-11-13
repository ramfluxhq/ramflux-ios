// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData

@Observable @MainActor public final class AppShellViewModel {
    public private(set) var state: AppShellState
    private let repository: any SessionRepository
    private let emit: @MainActor (AppShellEvent) -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    public init(repository: any SessionRepository, state: AppShellState = AppShellState(), emit: @escaping @MainActor (AppShellEvent) -> Void) {
        self.repository = repository; self.state = state; self.emit = emit
    }
    public func send(_ action: AppShellAction) {
        switch action {
        case .appeared:
            observe(); activate()
        case .sceneActive, .retry: observe(); activate()
        case .sceneInactive: conceal()
        case .sceneBackground:
            conceal(); suspend()
        case .disappeared:
            conceal(); updates?.cancel(); updates = nil; suspend()
        case .selectTab(let tab): state.tab = tab
        case .open(let route):
            guard !state.privacyShield else { return }
            emit(.navigate(route))
        case .openAccounts:
            guard !state.privacyShield else { return }; emit(.showAccounts)
        case .selectAccount(let id): select(id)
        case .deepLink(let url):
            guard !state.privacyShield, state.session.phase == .ready, state.session.activeAccountID != nil,
                  let route = AppRoute.parse(url) else { return }
            emit(.navigate(route))
        }
    }
    private func observe() {
        guard updates == nil else { return }
        updates = Task { [weak self, repository] in
            let stream = await repository.snapshots()
            for await value in stream {
                guard !Task.isCancelled, let self else { return }
                if !self.state.privacyShield { self.state.session = value }
            }
        }
    }
    private func activate() {
        generation &+= 1; let epoch = generation
        work?.cancel(); state.busy = true; state.failure = nil
        work = Task { [weak self, repository] in
            let result = await repository.activate()
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            self.state.busy = false; self.state.privacyShield = false
            switch result {
            case .success(let snapshot): self.state.session = snapshot
            case .failure(let failure): self.state.failure = failure; self.state.session = SessionSnapshot(phase: .failed(failure))
            }
        }
    }
    private func conceal() {
        generation &+= 1; work?.cancel()
        state.privacyShield = true; state.busy = false; state.failure = nil
        state.session = SessionSnapshot(phase: .suspended)
        emit(.dismissPrivateNavigation)
    }
    private func suspend() {
        generation &+= 1; let epoch = generation
        work?.cancel()
        work = Task { [weak self, repository] in
            let result = await repository.suspend()
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            if case .failure(let failure) = result { self.state.failure = failure }
        }
    }
    private func select(_ id: String) {
        guard !state.busy, !state.privacyShield, state.session.phase == .ready,
              state.session.accounts.contains(where: { $0.id == id }) else { return }
        generation &+= 1; let epoch = generation
        state.busy = true; state.failure = nil
        work?.cancel()
        work = Task { [weak self, repository] in
            let result = await repository.selectAccount(id)
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            self.state.busy = false
            switch result {
            case .success(let snapshot): self.state.session = snapshot; self.emit(.accountSelected)
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    /// Coordinator/test lifecycle barrier. The UI only emits Actions.
    public func settle() async { await work?.value }
    deinit { work?.cancel(); updates?.cancel() }
}
