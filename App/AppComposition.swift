// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
import FeatureAppShell
import FeatureOnboarding
import FeatureConversations
@MainActor final class AppComposition {
    let repositories: AppRepositories
    let shell: AppShellCoordinator
    lazy var onboarding = OnboardingCoordinator(repository: repositories.onboarding, nodes: repositories.nodes) { [weak self] account in
        self?.shell.path = []
        if account != nil { self?.shell.send(.retry) }
    }
    private var inbox: (String, ConversationsCoordinator)?
    func conversations(account: String) -> ConversationsCoordinator {
        if let inbox, inbox.0 == account { return inbox.1 }
        inbox?.1.send(.disappeared)
        let coordinator = ConversationsCoordinator(repository: repositories.conversations, account: account) { [weak self] route in self?.shell.send(.open(route)) }
        inbox = (account, coordinator); return coordinator
    }
    init() { let repositories = AppDataFactory.repositories(); self.repositories = repositories; shell = AppShellCoordinator(repository: repositories.session) }
}
