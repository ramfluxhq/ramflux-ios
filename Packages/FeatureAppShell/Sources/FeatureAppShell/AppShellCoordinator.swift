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
    /// Closes the unlock step (after an explicit lock or sign-out the code is asked; nothing else
    /// closes the screens, so there is nothing to reopen).
    public func closeUnlock() {
        sheet = nil
        path = []
    }
    private func handle(_ event: AppShellEvent) {
        switch event {
        case .navigate(let route): sheet = nil; path.append(route)
        case .showAccounts: sheet = .accounts
        case .accountSelected: path = []; sheet = nil
        case .showChatList: path = []; sheet = nil
        }
    }
}
