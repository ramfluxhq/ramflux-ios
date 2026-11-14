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
import FeaturePermissions
import FeatureCards
import FeatureTasks
import FeatureAgents
import FeatureCalls
import FeatureGroups
import Observation
@Observable @MainActor final class AppComposition {
    let repositories: AppRepositories
    let shell: AppShellCoordinator
    @ObservationIgnored lazy var devicePermissions = NativeDevicePermissionsRepository()
    @ObservationIgnored lazy var permissions = PermissionsCoordinator(repository: devicePermissions)
    @ObservationIgnored lazy var onboarding = OnboardingCoordinator(repository: repositories.onboarding, nodes: repositories.nodes, created: { [weak self] account in self?.permissions.send(.accountCreated(account.id)) }) { [weak self] account in
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
    @ObservationIgnored private var currentChat: (String, String, Bool, ChatCoordinator)?
    func chat(account: String, conversation: String, isGroup: Bool = false, title: String? = nil) -> ChatCoordinator {
        if let currentChat, currentChat.0 == account, currentChat.1 == conversation, currentChat.2 == isGroup { return currentChat.3 }
        currentChat?.3.send(.disappeared)
        let coordinator = ChatCoordinator(repository: repositories.chat, account: account, conversation: conversation, isGroup: isGroup, title: title) { [weak self] event in if case .navigate(let route) = event { self?.shell.send(.open(route)) } }
        currentChat = (account, conversation, isGroup, coordinator); return coordinator
    }
    @ObservationIgnored private var currentContacts: (String, ContactsMode, ContactsCoordinator)?
    func contacts(account: String, mode: ContactsMode) -> ContactsCoordinator {
        if let currentContacts, currentContacts.0 == account, currentContacts.1 == mode { return currentContacts.2 }
        currentContacts?.2.send(.disappeared)
        let coordinator = ContactsCoordinator(repository: repositories.contacts, account: account, mode: mode) { [weak self] route in self?.shell.send(.open(route)) }
        currentContacts = (account, mode, coordinator); return coordinator
    }
    @ObservationIgnored private var currentGroups: (String, GroupsCoordinator)?
    func groups(account: String) -> GroupsCoordinator {
        if let currentGroups, currentGroups.0 == account { return currentGroups.1 }
        currentGroups?.1.send(.disappeared)
        let coordinator = GroupsCoordinator(repository: repositories.groups, contacts: repositories.contacts, account: account) { [weak self] event in if case .navigate(let route) = event { self?.shell.send(.open(route)) } }
        currentGroups = (account, coordinator); return coordinator
    }
    @ObservationIgnored private var currentCalls: (String, CallsMode, CallsCoordinator)?
    func calls(account: String, conversation: String?) -> CallsCoordinator {
        let mode: CallsMode = conversation.map { .dial($0) } ?? .history
        if let currentCalls, currentCalls.0 == account, currentCalls.1 == mode { return currentCalls.2 }
        currentCalls?.2.send(.disappeared)
        let coordinator = CallsCoordinator(repository: repositories.calls, microphone: repositories.microphone, account: account, mode: mode)
        currentCalls = (account, mode, coordinator); return coordinator
    }
    @ObservationIgnored private var currentAgents: (String, AgentsCoordinator)?
    func agents(account: String) -> AgentsCoordinator {
        if let currentAgents, currentAgents.0 == account { return currentAgents.1 }
        currentAgents?.1.send(.disappeared)
        let coordinator = AgentsCoordinator(repository: repositories.agents, account: account)
        currentAgents = (account, coordinator); return coordinator
    }
    @ObservationIgnored private var currentTasks: (String, Bool, TasksCoordinator)?
    func tasks(account: String, permissions: Bool) -> TasksCoordinator {
        if let currentTasks, currentTasks.0 == account, currentTasks.1 == permissions { return currentTasks.2 }
        currentTasks?.2.send(.disappeared)
        let coordinator = TasksCoordinator(repository: repositories.tasks, conversations: repositories.conversations, account: account, mode: permissions ? .permissions : .conversations)
        currentTasks = (account, permissions, coordinator); return coordinator
    }
    @ObservationIgnored lazy var cards = CardsCoordinator(repository: repositories.cards)
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
