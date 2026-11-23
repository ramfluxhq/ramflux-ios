// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class SettingsCoordinator {
    public let viewModel: SettingsViewModel
    public let backup: BackupViewModel
    public init(repository: any SettingsRepository, backup: any BackupRepository, nodes: any NodeRepository, preferences: any PreferencesRepository, account: String?, route: AppRoute = .settings, onEvent: @escaping (SettingsEvent) -> Void) {
        viewModel = SettingsViewModel(repository: repository, nodes: nodes, preferences: preferences, account: account, state: SettingsState(route: route), emit: onEvent)
        self.backup = BackupViewModel(repository: backup, account: account, emit: onEvent)
    }
    public func send(_ action: BackupAction) { backup.send(action) }
    public func send(_ action: SettingsAction) { viewModel.send(action) }
}
