// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
import FeatureAppShell
import FeatureOnboarding
@MainActor final class AppComposition {
    let repositories: AppRepositories
    let shell: AppShellCoordinator
    lazy var onboarding = OnboardingCoordinator(repository: repositories.onboarding, nodes: repositories.nodes) { [weak self] account in
        self?.shell.path = []
        if account != nil { self?.shell.send(.retry) }
    }
    init() { let repositories = AppDataFactory.repositories(); self.repositories = repositories; shell = AppShellCoordinator(repository: repositories.session) }
}
