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
import FeatureTasks
import FeatureAgents
import FeatureCalls
import FeatureGroups
import RFMedia
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
    @ObservationIgnored private var currentChat: (String, String, String?, ChatCoordinator)?
    /// Opens a conversation; `group` is the SDK `group_id` of a group conversation (nil for a direct one).
    func chat(account: String, conversation: String, group: String? = nil, title: String? = nil) -> ChatCoordinator {
        if let currentChat, currentChat.0 == account, currentChat.1 == conversation, currentChat.2 == group { return currentChat.3 }
        currentChat?.3.send(.disappeared)
        let coordinator = ChatCoordinator(repository: repositories.chat, cards: repositories.cards, account: account, conversation: conversation, isGroup: group != nil, groupID: group, title: title) { [weak self] event in
            self?.chatEvent(event, account: account, conversation: conversation)
        }
        currentChat = (account, conversation, group, coordinator); return coordinator
    }
    /// A message waiting for its forward target; drives the conversation picker sheet.
    struct ForwardRequest: Identifiable, Equatable { let id: String; let account: String; let conversation: String }
    var forwarding: ForwardRequest?
    private func chatEvent(_ event: ChatEvent, account: String, conversation: String) {
        switch event {
        case .navigate(let route): shell.send(.open(route))
        case .requestPermission(let permission):
            requestPermission(permission) { [weak self] granted in self?.openChat(account, conversation)?.send(.permissionResolved(permission, granted: granted)) }
        case .chooseForwardTarget(let message): forwarding = ForwardRequest(id: message, account: account, conversation: conversation)
        case .messageSubmitted: break
        }
    }
    /// The picker closed: forwards to the chosen conversation, or does nothing when it was cancelled.
    func forwardChosen(_ target: ForwardTarget?) {
        guard let request = forwarding else { return }
        forwarding = nil
        guard let target, let chat = openChat(request.account, request.conversation) else { return }
        chat.send(.forwardTo(messageID: request.id, conversation: target.conversation, groupID: target.groupID))
    }
    private func openChat(_ account: String, _ conversation: String) -> ChatCoordinator? {
        guard let currentChat, currentChat.0 == account, currentChat.1 == conversation else { return nil }
        return currentChat.3
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
        let coordinator = CallsCoordinator(repository: repositories.calls, microphone: repositories.microphone, account: account, mode: mode, permissions: self,
                                           peerNames: ContactCallPeerNames(contacts: repositories.contacts)) { [weak self] row in
            guard let service = self?.callService else { return }
            Task { await service.outgoingStarted(row) }
        }
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
            case .locked: self?.accountLocked(); self?.shell.path = []; self?.shell.send(.retry)
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
        guard session.activeAccountID != unlockedAccount else { return }
        unlockedAccount = session.activeAccountID
        callService.stop()
        guard let account = session.activeAccountID else { return }
        // After unlock: queued sends resume with their operation ids, and the system call UI follows the account.
        Task { [chat = repositories.chat] in _ = await chat.resumeAfterUnlock(account: account) }
        callService.start(account: account)
    }
    /// The account the composition last saw unlocked; calls and the outbox follow it.
    @ObservationIgnored private var unlockedAccount: String?
    /// One system call integration per process (one CallKit provider). It reports nothing while the
    /// media engine refuses (see docs/app-shell.md, "Calls and the media engine boundary").
    @ObservationIgnored private(set) lazy var callService = CallSystemService(repository: repositories.calls, provider: CallKitProvider(supportsVideo: false), audio: CallAudioSession())
    private func accountLocked() { unlockedAccount = nil; callService.stop() }
    /// Account-scoped stores react before the SDK locks or removes the account.
    private func registerLifecycle() {
        repositories.lifecycle.register { [weak self, chat = repositories.chat] event in
            switch event {
            case .willLock(let account):
                await MainActor.run { self?.accountLocked() }
                await chat.sealForLock(account: account)
                ImagePipeline.shared.purge()
            case .willRemove(let account):
                await MainActor.run { self?.accountLocked() }
                await chat.purgeAccount(account: account)
                ImagePipeline.shared.purge()
            }
        }
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
        registerLifecycle()
    }
}
/// Calls ask for the microphone and camera through the shared explanation flow.
extension AppComposition: CallPermissionRequesting {}
