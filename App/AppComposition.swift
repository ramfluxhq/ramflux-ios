// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RFDesign
import AppData
import FeatureAppShell
import FeatureOnboarding
import FeatureConversations
import FeatureChat
import FeatureContacts
import FeatureSettings
import Observation
@Observable @MainActor final class AppComposition {
    let repositories: AppRepositories
    let shell: AppShellCoordinator
    @ObservationIgnored lazy var onboarding = OnboardingCoordinator(repository: repositories.onboarding, nodes: repositories.nodes) { [weak self] account in
        self?.shell.path = []
        if account != nil { self?.shell.send(.retry) }
    }
    @ObservationIgnored private var inbox: (String, ConversationsCoordinator)?
    func conversations(account: String) -> ConversationsCoordinator {
        if let inbox, inbox.0 == account { return inbox.1 }
        inbox?.1.send(.disappeared)
        let coordinator = ConversationsCoordinator(repository: repositories.conversations, account: account) { [weak self] route in self?.shell.send(.open(route)) }
        inbox = (account, coordinator); return coordinator
    }
    @ObservationIgnored private var currentChat: (String, String, ChatCoordinator)?
    func chat(account: String, conversation: String) -> ChatCoordinator {
        if let currentChat, currentChat.0 == account, currentChat.1 == conversation { return currentChat.2 }
        currentChat?.2.send(.disappeared)
        let coordinator = ChatCoordinator(repository: repositories.chat, account: account, conversation: conversation)
        currentChat = (account, conversation, coordinator); return coordinator
    }
    @ObservationIgnored private var currentContacts: (String, ContactsMode, ContactsCoordinator)?
    func contacts(account: String, mode: ContactsMode) -> ContactsCoordinator {
        if let currentContacts, currentContacts.0 == account, currentContacts.1 == mode { return currentContacts.2 }
        currentContacts?.2.send(.disappeared)
        let coordinator = ContactsCoordinator(repository: repositories.contacts, account: account, mode: mode) { [weak self] route in self?.shell.send(.open(route)) }
        currentContacts = (account, mode, coordinator); return coordinator
    }
    var appearance: AppearanceMode = .system
    @ObservationIgnored private var preferenceTask: Task<Void, Never>?
    @ObservationIgnored private var currentSettings: (String?, AppRoute, SettingsCoordinator)?
    func settings(account: String?, route: AppRoute) -> SettingsCoordinator {
        if let currentSettings, currentSettings.0 == account, currentSettings.1 == route { return currentSettings.2 }
        currentSettings?.2.send(.disappeared)
        let coordinator = SettingsCoordinator(repository: repositories.settings, backup: repositories.backup, nodes: repositories.nodes,
            preferences: repositories.preferences, account: account, route: route) { [weak self] event in
            switch event {
            case .navigate(let route): self?.shell.send(.open(route))
            case .locked: self?.shell.path = []; self?.shell.send(.retry)
            case .appearanceChanged(let mode): self?.appearance = mode
            }
        }
        currentSettings = (account, route, coordinator); return coordinator
    }
    func startPreferences() {
        preferenceTask?.cancel()
        preferenceTask = Task { [weak self, preferences = repositories.preferences] in
            let mode = await preferences.appearance(); guard !Task.isCancelled else { return }; self?.appearance = mode
        }
    }
    deinit { preferenceTask?.cancel() }
    init() { _ = DesignFonts.registered; let repositories = AppDataFactory.repositories(); self.repositories = repositories; shell = AppShellCoordinator(repository: repositories.session) }
}
