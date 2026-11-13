// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData
public enum AppShellSheet: String, Identifiable { case accounts; public var id: Self { self } }
@Observable @MainActor public final class AppShellCoordinator {
    public var path: [AppRoute] = []
    public var sheet: AppShellSheet?
    private let repository: any SessionRepository
    @ObservationIgnored public lazy var viewModel = AppShellViewModel(repository: repository) { [weak self] event in self?.handle(event) }
    public init(repository: any SessionRepository) { self.repository = repository }
    public func send(_ action: AppShellAction) { viewModel.send(action) }
    private func handle(_ event: AppShellEvent) {
        switch event {
        case .navigate(let route): path.append(route)
        case .showAccounts: sheet = .accounts
        case .accountSelected, .dismissPrivateNavigation: path = []; sheet = nil
        }
    }
}
