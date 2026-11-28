// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UIKit
import SwiftUI
import RFDesign
import RFLocalization
import AppData
import FeatureAppShell
import FeatureOnboarding
import FeatureConversations
import FeatureChat
import FeatureContacts
import FeatureSettings
import FeaturePermissions
import FeatureDelivery
import FeatureTasks
import FeatureAgents
import FeatureCalls
import FeatureGroups
import RFMedia
import Observation
import UserNotifications
import Push
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
    /// The locked state of a pushed screen: the lock page of the first locked account, or, when the device lists none, the way to the picker.
    func lockedScreen(message: String) -> AnyView {
        if let account = shell.viewModel.state.session.accounts.first(where: \.isLocked) { return lockPage(for: account, pushed: true) }
        return AnyView(LockedScreen(message: message, onAccounts: { [weak self] in self?.shell.send(.openAccounts) }))
    }
    /// The lock page of a locked account (not the app lock): the code field, the states and Unlock, or the recovery inside it.
    /// `pushed` pages (opened from the picker) carry a back control; the root one, which replaces the tabs, does not.
    func lockPage(for account: AccountRecord, pushed: Bool) -> AnyView {
        if let recovery = lockRecovery(for: account.id) { return AnyView(OnboardingHost(coordinator: recovery)) }
        let several = shell.viewModel.state.session.accounts.count > 1
        return AnyView(AccountLockPage(model: appLock(account: account.id), onBack: pushed ? { [weak self] in self?.shell.closeUnlock() } : nil,
                                       onSwitchAccount: several ? { [weak self] in self?.shell.send(.openAccounts) } : nil))
    }
    /// The app lock's code field for the active account. Success re-activates the shell only: the navigation
    /// path and any sheet stay as they were, so the same conversation is back underneath.
    /// One model per account id: a lock page pushed over another one keeps its own removal state and name.
    @ObservationIgnored private var appLockScreens: [String: AppLockModel] = [:]
    func appLock(account: String) -> AppLockModel {
        // The one account this page is bound to, by id, as `account.list` names it (only its own name and initial are drawn).
        let record = shell.viewModel.state.session.accounts.first { $0.id == account }
        if let existing = appLockScreens[account] {
            if let record, existing.account != record { existing.account = record }
            return existing
        }
        let model = AppLockModel(repository: repositories.onboarding, settings: repositories.settings, account: account, record: record,
                                 onUnlocked: { [weak self] in
                                    // A lock page opened from the picker is a pushed route: it leaves with the unlock. The app lock never moves the navigation.
                                    if self?.shell.path.contains(.unlockAccount(account)) == true { self?.shell.closeUnlock() }
                                    self?.shell.send(.retry) }, onRestore: { [weak self] in self?.restoreFromLock(account: account) },
                                 onRemoved: { [weak self] in self?.lockedAccountRemoved(account) })
        appLockScreens[account] = model; return model
    }
    /// Shown at the top after an account was removed from this device ("<name> was removed from this device."); clears itself.
    private(set) var removedNotice: String?
    @ObservationIgnored private var removedNoticeTask: Task<Void, Never>?
    /// The SDK erased the locked account (`account.remove_local`). Drop what the client holds for it, forget the cover's
    /// state and go where the app goes when an account disappears: the shell reads the accounts again and shows the
    /// account picker when others exist, onboarding otherwise.
    private func lockedAccountRemoved(_ account: String) {
        // The name is read before anything else changes: the session no longer lists the account once it is read again.
        let record = appLockScreens[account]?.account ?? shell.viewModel.state.session.accounts.first { $0.id == account }
        let name = (record ?? AccountRecord(id: account, displayName: "", isLocked: true)).title()
        showRemovedNotice(name)
        clearLockRecovery()
        appLockScreens[account] = nil
        accountLocked()
        shell.path = []
        shell.send(.retry)
        landAfterRemoval()
    }
    /// The shell has no screen of its own for "no account": once the session is re-read, land on the account picker when
    /// other accounts remain, on onboarding otherwise, instead of leaving the old tab on screen.
    private func landAfterRemoval() {
        Task { [weak self] in
            await self?.shell.viewModel.settle()
            guard let self, !self.shell.viewModel.state.privacyShield, self.shell.viewModel.state.session.phase == .ready,
                  self.shell.viewModel.state.session.activeAccountID == nil else { return }
            self.shell.send(.selectTab(.messages))
            if self.shell.viewModel.state.session.accounts.isEmpty { self.shell.send(.open(.onboarding)) } else { self.shell.send(.openAccounts) }
        }
    }
    /// An account was removed from the Settings page: the same landing and toast as a removal from the lock page.
    private func accountRemovedFromSettings(_ name: String) {
        showRemovedNotice(name)
        accountLocked(); shell.path = []; shell.send(.retry)
        landAfterRemoval()
    }
    private func showRemovedNotice(_ name: String) {
        removedNotice = RFSentence.compose(RamfluxAppStrings.text("app.removed.notice"), [.untrusted(name)], locale: .current)
        removedNoticeTask?.cancel()
        removedNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.removedNotice = nil
        }
    }
    /// The recovery flow the lock cover shows in place of the lock form after Restore on an exhausted lock, keyed by the
    /// locked account. It is drawn inside the cover, so no shell route opens under it and no account content is reached.
    /// Back dismisses it. It is cleared when the app goes to the background and when the lock lifts.
    private(set) var lockRecovery: (account: String, coordinator: OnboardingCoordinator)?
    /// The recovery flow for `account` while the cover shows that account's lock; nil for any other account.
    func lockRecovery(for account: String) -> OnboardingCoordinator? {
        guard let lockRecovery, lockRecovery.account == account else { return nil }
        return lockRecovery.coordinator
    }
    func restoreFromLock(account: String) {
        guard lockRecovery == nil else { return }
        // A refusal that moves the lock screen closes the recovery; the cover reads the app-lock state again and shows the
        // lock form with the countdown or the exhausted page. A success keeps the cover until the state says unlocked.
        let coordinator = OnboardingCoordinator(repository: repositories.onboarding, nodes: repositories.nodes, initialState: .recoverLockedAccount(account, name: appLockScreens[account]?.account?.displayName ?? shell.viewModel.state.session.accounts.first { $0.id == account }?.displayName ?? ""),
            lockRecoveryEnded: { [weak self] failure in
                self?.lockRecovery = nil
                self?.appLockScreens[account]?.recoveryEnded(failure)
            }) { [weak self] recovered in
            self?.lockRecovery = nil
            if recovered != nil { self?.shell.send(.retry) }
        }
        lockRecovery = (account, coordinator)
    }
    /// Drops the lock's recovery flow so the next lock shows the code form, not the recovery page.
    func clearLockRecovery() {
        lockRecovery?.coordinator.send(.disappeared)
        lockRecovery = nil
        for model in appLockScreens.values { model.conceal() }
    }
    @ObservationIgnored private var inbox: (String, String, ConversationsCoordinator)?
    func conversations(account: String) -> ConversationsCoordinator {
        let title = shell.viewModel.state.session.accounts.first { $0.id == account }?.displayName ?? ""
        // The title is part of the coordinator: while the app lock is engaged the SDK hides the account's name, so the
        // inbox is built again once the real name is back after the unlock.
        if let inbox, inbox.0 == account, inbox.1 == title { return inbox.2 }
        inbox?.2.send(.disappeared)
        let coordinator = ConversationsCoordinator(repository: repositories.conversations, account: account, accountTitle: title) { [weak self] route in self?.shell.send(.open(route)) }
        inbox = (account, title, coordinator); return coordinator
    }
    @ObservationIgnored private var currentChat: (String, String, String?, ChatCoordinator)?
    /// Opens a conversation; `group` is the SDK `group_id` of a group conversation (nil for a direct one).
    func chat(account: String, conversation: String, group: String? = nil, title: String? = nil) -> ChatCoordinator {
        if let currentChat, currentChat.0 == account, currentChat.1 == conversation, currentChat.2 == group { return currentChat.3 }
        currentChat?.3.send(.disappeared)
        // A direct conversation takes the name its directory row resolved (contact name or short identifier).
        let row = inbox.flatMap { $0.0 == account ? $0.2.viewModel.state.rows.first { $0.id == conversation } : nil }
        let resolved = title ?? row?.title
        let coordinator = ChatCoordinator(repository: repositories.chat, cards: repositories.cards, account: account, conversation: conversation, isGroup: group != nil, groupID: group, title: resolved,
                                          peerIsAgent: group == nil && row?.classification.isAIAgent == true) { [weak self] event in
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
    /// Closes every presented sheet (account picker, forward target, permission prompts) while the cover rises.
    func dismissPresentedSheets() {
        shell.sheet = nil
        forwardChosen(nil)
        let permission = permissions.viewModel.state
        if permission.explanation != nil { permissions.send(.cancelExplanation) }
        if permission.permissionNeeded != nil { permissions.send(.dismissNeeded) }
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
    /// One coordinator per Settings page on the navigation path, for one account. Settings pages stack (Settings, Account,
    /// Privacy, App lock), and SwiftUI rebuilds every destination on the path when the shell changes: a single cached page
    /// made each rebuild replace the others, so the page on top lost its state and its pending change.
    @ObservationIgnored private var settingsPages: [AppRoute: SettingsCoordinator] = [:]
    @ObservationIgnored private var settingsAccount: String?
    func settings(account: String?, route: AppRoute) -> SettingsCoordinator {
        // A nil account is the shell reporting none for a moment (a foreground still opening, a failed activation), not a
        // different account: the open pages keep their account and their state. Only a real change replaces them.
        if let account, account != settingsAccount {
            settingsPages.values.forEach(retireSettings); settingsPages = [:]; settingsAccount = account
        }
        // Pages popped off the path are released; the rest keep their coordinator.
        for (open, page) in settingsPages where open != route && !shell.path.contains(open) { retireSettings(page); settingsPages[open] = nil }
        if let page = settingsPages[route] { return page }
        let owner = account ?? settingsAccount
        let coordinator = SettingsCoordinator(repository: repositories.settings, backup: repositories.backup, pairing: repositories.pairing, nodes: repositories.nodes,
            preferences: repositories.preferences, account: owner, accountRecord: shell.viewModel.state.session.accounts.first { $0.id == owner }, route: route) { [weak self] event in
            switch event {
            case .navigate(let route): self?.shell.send(.open(route))
            case .locked: self?.accountLocked(); self?.shell.path = []; self?.shell.send(.retry)
            case .appearanceChanged(let mode): self?.appearance = mode
            case .appLockChanged(let enabled): Task { [session = self?.repositories.session] in await session?.appLockConfigured(enabled: enabled) }
            case .restored: self?.shell.path = []; self?.shell.send(.retry)
            case .removed(let name): self?.accountRemovedFromSettings(name)
            case .openSystemSettings: if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        settingsPages[route] = coordinator; return coordinator
    }
    private func retireSettings(_ page: SettingsCoordinator) {
        page.send(SettingsAction.disappeared); page.send(BackupAction.disappeared); page.send(PairingAction.disappeared)
    }
    /// Local message notifications while the app is not active (see docs/permissions.md).
    @ObservationIgnored lazy var notifier = MessageNotifier(conversations: repositories.conversations, center: NativeMessageNotificationCenter())
    @ObservationIgnored private var notificationDelegate: MessageNotificationDelegate?
    /// The Settings delivery page for the active account.
    @ObservationIgnored private(set) lazy var delivery = DeliveryCoordinator(repository: repositories.delivery, account: { [weak self] in self?.shell.viewModel.state.session.activeAccountID })
    /// Registers the unlocked account's push route (Debug builds: the raw token, to the developer's own node).
    @ObservationIgnored lazy var routeRegistrar = RouteRegistrar(repository: repositories.pushRoutes, registry: RouteRegistry(), store: DeliveryLocalStore())
    /// The in-app banner on screen, if any. It lives in memory only: never logged, restored or donated.
    var banner: InAppBanner?
    /// New incoming messages while the app is in the foreground, from the same directory stream as the
    /// notifier; the conversation on screen, muted conversations and own messages raise nothing.
    @ObservationIgnored lazy var bannerFeed = InAppBannerFeed(conversations: repositories.conversations, chat: repositories.chat,
        isOpen: { [weak self] id in self?.isConversationOpen(id) ?? false }, deliver: { [weak self] banner in self?.banner = banner })
    private func isConversationOpen(_ id: String) -> Bool {
        switch shell.path.last {
        case .conversation(let open)?: open == id
        case .groupConversation(let open, _, _)?: open == id
        default: false
        }
    }
    /// A tap on the banner opens its conversation through the shell's route policy; while the app is locked
    /// the shell holds the route until the unlock completes.
    func openBanner(_ banner: InAppBanner) {
        self.banner = nil
        shell.send(.openWhenReady(banner.route, account: banner.account))
    }
    func dismissBanner(_ id: UUID) { if banner?.id == id { banner = nil } }
    /// The scene is about to become inactive: no banner may be on screen for the snapshot.
    private func sceneResigning() { banner = nil; bannerFeed.setForeground(false) }
    /// Follows the active unlocked account; a locked session stops notifications, a concealed one keeps them.
    func sessionChanged(_ session: SessionSnapshot) {
        // The lock-recovery state is keyed by the locked account: a change of account drops it (G05f audit F4).
        if let lockRecovery, lockRecovery.account != session.activeAccountID { clearLockRecovery() }
        // Not ready (opening, failed, stopped): nothing of the account is followed for banners or notifications.
        guard session.phase == .ready else { notifier.follow(account: nil); bannerFeed.follow(account: nil); banner = nil; return }
        // An engaged app lock: nothing of the account runs (notifications, banners, calls, sends) until the code is entered.
        // The delivered notifications go with the lock; while it is on, posts carry only the generic "New message".
        guard !session.appLocked else { notifier.follow(account: nil); bannerFeed.follow(account: nil); notifier.appLockEngaged(); lockWasEngaged = true; accountLocked(); return }
        if lockWasEngaged { lockWasEngaged = false; clearLockRecovery(); reloadScreensAfterAppLock() }
        notifier.follow(account: session.activeAccountID)
        bannerFeed.follow(account: session.activeAccountID)
        if banner?.account != session.activeAccountID { banner = nil }
        guard session.activeAccountID != unlockedAccount else { return }
        unlockedAccount = session.activeAccountID
        callService.stop()
        guard let account = session.activeAccountID else { return }
        // After unlock: queued sends resume with their operation ids, and the system call UI follows the account.
        Task { [chat = repositories.chat] in _ = await chat.resumeAfterUnlock(account: account) }
        callService.start(account: account)
        Task { [routeRegistrar] in await routeRegistrar.register(account: account) }
    }
    /// The app lock was engaged and has not been released yet.
    @ObservationIgnored private var lockWasEngaged = false
    /// The code was accepted: the screens kept as they were (same navigation path) failed their reads while the lock was
    /// engaged, so each open one reads again instead of showing the locked state it caught.
    private func reloadScreensAfterAppLock() {
        inbox?.2.send(.refresh)
        currentChat?.3.send(.refresh)
        currentContacts?.2.send(.refresh)
        currentGroups?.1.send(.refresh)
        currentCalls?.2.send(.refresh)
        currentAgents?.1.send(.retry)
        currentTasks?.2.send(.refresh)
        for (route, page) in settingsPages where shell.path.contains(route) { page.send(SettingsAction.refresh) }
    }
    /// The account the composition last saw unlocked; calls and the outbox follow it.
    @ObservationIgnored private var unlockedAccount: String?
    /// One system call integration per process (one CallKit provider). It reports nothing while the
    /// media engine refuses (see docs/app-shell.md, "Calls and the media engine boundary").
    @ObservationIgnored private(set) lazy var callService = CallSystemService(repository: repositories.calls, provider: CallKitProvider(supportsVideo: false), audio: CallAudioSession())
    /// Call wakes that must ring (PushKit later, the debug injector now) report a placeholder to the system call UI.
    @ObservationIgnored private(set) lazy var callWakeHandler = CallWakeHandler(bridge: callService.bridge)
    /// A remote notification delivered to the app process (clears, debug wakes). Returns what the system is told.
    func handleRemoteWake(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        #if RAMFLUX_DEBUG_WAKE
        if let mode = DebugWakeInjector.mode(userInfo: userInfo) { await runDebugWake(mode, payload: WakePayload(userInfo: userInfo)); return .newData }
        #endif
        let output = await WakeHost.processor().process(payload: WakePayload(userInfo: userInfo), original: nil, source: .remoteNotification)
        // Only a clear acts here (it removes the generic notification); there is nothing to fetch for a background push.
        return output.result == .clearMessages ? .newData : .noData
    }
    #if RAMFLUX_DEBUG_WAKE
    /// Runs a wake through the shared processor with the debug source and logs the result kind only.
    func runDebugWake(_ mode: DebugWakeInjector.Mode, payload: WakePayload) async {
        let processor = WakeHost.processor()
        let output = await processor.process(payload: payload, original: nil, source: mode == .remote ? .remoteNotification : .debugInjector, overrideClass: mode == .nse ? .message : nil)
        PushLog.wake.notice("push.debug.result \(String(describing: output.result).prefix(40), privacy: .public)")
        if case .ringCall = output.result { await callWakeHandler.ring() }
    }
    #endif
    private func accountLocked() { unlockedAccount = nil; banner = nil; callService.stop() }
    /// The scene is active again: the SDK resumed without asking for anything and the account stayed
    /// unlocked, so a send the suspension interrupted (it completes as suspended and stays queued) is
    /// flushed again with its operation id once the session is back.
    func returnedToForeground() {
        Task { [weak self, chat = repositories.chat] in
            await self?.shell.viewModel.settle()
            guard let account = self?.unlockedAccount else { return }
            _ = await chat.resumeAfterUnlock(account: account)
        }
    }
    /// Account-scoped stores react before the SDK locks or removes the account.
    private func registerLifecycle() {
        repositories.lifecycle.register { [weak self, chat = repositories.chat] event in
            switch event {
            case .willLock(let account):
                await MainActor.run { self?.accountLocked() }
                await chat.sealForLock(account: account)
                ImagePipeline.shared.purge()
            case .willLeave(let account):
                await self?.routeRegistrar.deregister(account: account)
            case .willRemove(let account):
                await MainActor.run { self?.accountLocked() }
                await chat.purgeAccount(account: account)
                ImagePipeline.shared.purge()
            }
        }
    }
    private func openNotification(_ token: String) {
        guard let account = notifier.account(for: token) else { return }
        shell.send(.openWhenReady(nil, account: account))
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
        UNUserNotificationCenter.current().setNotificationCategories(MessageNotificationSlot.categories())
        registerLifecycle()
        AppDelegate.remoteWake = { [weak self] userInfo in await self?.handleRemoteWake(userInfo) ?? .noData }
        #if RAMFLUX_DEBUG_WAKE
        if let mode = DebugWakeInjector.launchMode() { Task { [weak self] in await self?.runDebugWake(mode, payload: WakePayload(userInfo: ["rf": ["v": 1, "c": mode == .voip ? "call" : (mode == .remote ? "x" : (mode == .test ? "t" : "m")), "t": RouteRegistry()?.anyTag() ?? "AAAAAAAAAAAAAAAAAAAAAA", "w": "debug-launch"]])) } }
        #endif
        #if RAMFLUX_DEBUG_WAKE
        if DebugWakeInjector.launchRoute() == "delivery" {
            Task { @MainActor [weak self] in
                for _ in 0..<80 {
                    if let account = self?.shell.viewModel.state.session.activeAccountID { self?.shell.send(.openWhenReady(.delivery, account: account)); return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        #endif
        ApnsTokenSource.shared.onChange { [weak self] in Task { await self?.routeRegistrar.tokenChanged() } }
        PrivacyCover.install(appearance: { [weak self] in self?.appearance.rawValue ?? "system" }, resigning: { [weak self] in self?.sceneResigning() },
                             activated: { [weak self] in self?.bannerFeed.setForeground(true) },
                             holdsForAppLock: { [weak self] in self?.shell.viewModel.state.session.appLockEnabled != false })
    }
}
/// Calls ask for the microphone and camera through the shared explanation flow.
extension AppComposition: CallPermissionRequesting {}
