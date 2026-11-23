// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UIKit
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
import UserNotifications
@Observable @MainActor final class AppComposition {
    let repositories: AppRepositories
    let shell: AppShellCoordinator
    @ObservationIgnored lazy var devicePermissions = NativeDevicePermissionsRepository()
    @ObservationIgnored lazy var permissions = PermissionsCoordinator(repository: devicePermissions) { [weak self] event in self?.permissionSettled(event) }
    @ObservationIgnored private var permissionWaiters: [DevicePermission: [@MainActor (Bool) -> Void]] = [:]
    /// Runs the permission explanation and system prompt for a feature and reports whether the
    /// permission is usable. Feature hosts receive this as their permission-request handler.
    func requestPermission(_ permission: DevicePermission, resolved: @escaping @MainActor (Bool) -> Void) {
        permissionWaiters[permission, default: []].append(resolved)
        permissions.send(.need(permission))
    }
    private func permissionSettled(_ event: PermissionsEvent) {
        let (permission, granted): (DevicePermission, Bool) = switch event { case .ready(let value): (value, true); case .declined(let value): (value, false) }
        let waiters = permissionWaiters.removeValue(forKey: permission) ?? []
        waiters.forEach { $0(granted) }
    }
    @ObservationIgnored lazy var onboarding = OnboardingCoordinator(repository: repositories.onboarding, nodes: repositories.nodes, created: { [weak self] account in self?.permissions.send(.accountCreated(account.id)) },
        restoreBackup: { [weak self] in self?.shell.send(.open(.backup)) }) { [weak self] account in
        self?.shell.path = []
        if account != nil { self?.shell.send(.retry) }
    }
    @ObservationIgnored private var inbox: (String, ConversationsCoordinator)?
    func conversations(account: String) -> ConversationsCoordinator {
        if let inbox, inbox.0 == account { return inbox.1 }
        inbox?.1.send(.disappeared)
        let title = shell.viewModel.state.session.accounts.first { $0.id == account }?.displayName ?? ""
        let coordinator = ConversationsCoordinator(repository: repositories.conversations, account: account, accountTitle: title) { [weak self] route in self?.shell.send(.open(route)) }
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
        let coordinator = AgentsCoordinator(repository: repositories.agents, account: account) { [weak self] event in if case .navigate(let route) = event { self?.shell.send(.open(route)) } }
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
        currentSettings?.2.send(SettingsAction.disappeared); currentSettings?.2.send(BackupAction.disappeared); currentSettings?.2.send(PairingAction.disappeared)
        let coordinator = SettingsCoordinator(repository: repositories.settings, backup: repositories.backup, pairing: repositories.pairing, nodes: repositories.nodes,
            preferences: repositories.preferences, account: account, route: route) { [weak self] event in
            switch event {
            case .navigate(let route): self?.shell.send(.open(route))
            case .locked: self?.shell.path = []; self?.shell.send(.retry)
            case .appearanceChanged(let mode): self?.appearance = mode
            case .restored: self?.shell.path = []; self?.shell.send(.retry)
            case .openSystemSettings: if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        currentSettings = (account, route, coordinator); return coordinator
    }
    /// Local message notifications while the app is not active (see docs/permissions.md).
    @ObservationIgnored lazy var notifier = MessageNotifier(conversations: repositories.conversations, center: NativeMessageNotificationCenter())
    @ObservationIgnored private var notificationDelegate: MessageNotificationDelegate?
    /// Follows the active unlocked account; a locked session stops notifications, a concealed one keeps them.
    func sessionChanged(_ session: SessionSnapshot) {
        guard session.phase == .ready else { return }
        notifier.follow(account: session.activeAccountID)
    }
    private func openNotification(_ token: String) {
        guard let target = notifier.route(for: token) else { return }
        shell.send(.openWhenReady(target.route, account: target.account))
    }
    func startPreferences() {
        preferenceTask?.cancel()
        preferenceTask = Task { [weak self, preferences = repositories.preferences] in
            let mode = await preferences.appearance(); guard !Task.isCancelled else { return }; self?.appearance = mode
        }
    }
    deinit { preferenceTask?.cancel() }
    init() { _ = DesignFonts.registered; let repositories = AppDataFactory.repositories(); self.repositories = repositories; shell = AppShellCoordinator(repository: repositories.session)
        let delegate = MessageNotificationDelegate { [weak self] token in self?.openNotification(token) }
        notificationDelegate = delegate; UNUserNotificationCenter.current().delegate = delegate
    }
}
