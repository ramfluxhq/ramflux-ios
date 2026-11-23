// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData
@Observable @MainActor public final class AppShellCoordinator {
    public var path: [AppRoute] = [] { didSet { EventDiagnostics.note("shell path \(path.map(Self.kind))") } }
    /// The route's case name only (no ids), for the debug trace.
    nonisolated static func kind(_ route: AppRoute) -> String { String(String(describing: route).prefix { $0 != "(" }) }
    public var sheet: AppShellSheet?
    public var shortcutOrder = ShellShortcuts.defaultOrder
    public var shortcutHidden = ""
    private let repository: any SessionRepository
    @ObservationIgnored public lazy var viewModel = AppShellViewModel(repository: repository) { [weak self] event in self?.handle(event) }
    public init(repository: any SessionRepository) { self.repository = repository }
    public func send(_ action: AppShellAction) { viewModel.send(action) }
    /// Closes the unlock step. When `account` was unlocked and had screens open when it was locked, they
    /// replace the unlock step in the same path change: a pop followed at once by a push lets the
    /// navigation stack finish the pop after the push and drop the reopened screen.
    public func closeUnlock(reopening account: String?) {
        sheet = nil
        path = account.map { viewModel.takeParked(for: $0) } ?? []
    }
    private func handle(_ event: AppShellEvent) {
        switch event {
        case .navigate(let route): sheet = nil; path.append(route)
        case .showAccounts: sheet = .accounts
        case .accountSelected: path = []; sheet = nil
        case .dismissPrivateNavigation: viewModel.park(path); path = []; sheet = nil
        }
    }
}
