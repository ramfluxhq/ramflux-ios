// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import FeatureAppShell
import AppData
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
import RFDesign

@main struct RamfluxApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var runtime = AppLifecycleCoordinator()
    @State private var composition = AppComposition()
    private var coordinator: AppShellCoordinator { composition.shell }
    private var appearance: AppearanceMode { composition.appearance }
    var body: some Scene {
        WindowGroup {
            RFThemeScope(selection: appearance.rawValue) { AppShellHost(coordinator: coordinator, tabContent: { tab, account in
                if tab == .messages, let account { return AnyView(VStack(spacing: 0) { NotificationPermissionBanner(state: composition.permissions.viewModel.state, onAction: composition.permissions.send); ConversationsHost(coordinator: composition.conversations(account: account)) }) }
                if tab == .groups, let account { return AnyView(GroupsHost(coordinator: composition.groups(account: account))) }
                if tab == .agents, let account { return AnyView(AgentsHost(coordinator: composition.agents(account: account))) }
                if tab == .more {
                    return AnyView(MoreHubScreen(
                        order: Binding(get: { coordinator.shortcutOrder }, set: { coordinator.shortcutOrder = $0 }),
                        hidden: Binding(get: { coordinator.shortcutHidden }, set: { coordinator.shortcutHidden = $0 }),
                        onAction: { coordinator.send($0) }
                    ))
                }
                return nil
            }) { route in
                switch route {
                case .systemPermissions: return AnyView(PermissionsHost(coordinator: composition.permissions))
                case .tasks, .permissions:
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(TasksHost(coordinator: composition.tasks(account: account, permissions: route == .permissions))) }
                    else { return AnyView(composition.lockedScreen(message: RamfluxAppStrings.text("app.locked.conversationMessage"))) }
                case .calls(let conversation):
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(CallsHost(coordinator: composition.calls(account: account, conversation: conversation))) }
                    else { return AnyView(composition.lockedScreen(message: RamfluxAppStrings.text("app.locked.conversationMessage"))) }
                case .groupConversation(let id, let group, let title):
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(ChatHost(coordinator: composition.chat(account: account, conversation: id, group: group, title: title))) }
                    else { return AnyView(composition.lockedScreen(message: RamfluxAppStrings.text("app.locked.conversationMessage"))) }
                case .conversation(let id):
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(ChatHost(coordinator: composition.chat(account: account, conversation: id))) }
                    else { return AnyView(composition.lockedScreen(message: RamfluxAppStrings.text("app.locked.conversationMessage"))) }
                case .mediaStorage:
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(MediaStorageHost(repository: composition.repositories.chat, account: account)) }
                    else { return AnyView(composition.lockedScreen(message: RamfluxAppStrings.text("app.locked.conversationMessage"))) }
                case .contacts, .strangers, .contact, .safetyNumber:
                    if let account = coordinator.viewModel.state.session.activeAccountID {
                        let mode: ContactsMode = switch route { case .strangers: .strangers; case .contact(let id): .profile(id); case .safetyNumber(let id): .safety(id); default: .contacts }
                        return AnyView(ContactsHost(coordinator: composition.contacts(account: account, mode: mode)))
                    } else { return AnyView(composition.lockedScreen(message: RamfluxAppStrings.text("app.locked.contactsMessage"))) }
                case .onboarding, .recoverAccount, .linkDevice: return AnyView(OnboardingHost(coordinator: composition.onboarding))
                case .unlockAccount(let account): return AnyView(OnboardingHost(coordinator: composition.unlock(account: account)))
                case .notices: return AnyView(NoticesScreen())
                case .shellNavigation:
                    return AnyView(NavigationEditorScreen(
                        order: Binding(get: { coordinator.shortcutOrder }, set: { coordinator.shortcutOrder = $0 }),
                        hidden: Binding(get: { coordinator.shortcutHidden }, set: { coordinator.shortcutHidden = $0 }),
                        onBack: { if !coordinator.path.isEmpty { coordinator.path.removeLast() } }
                    ))
                default: return AnyView(SettingsHost(coordinator: composition.settings(account: coordinator.viewModel.state.session.activeAccountID, route: route)))
                }
            }
            }
                .background(PermissionsPresentationHost(coordinator: composition.permissions))
                .sheet(item: Binding(get: { composition.forwarding }, set: { if $0 == nil { composition.forwardChosen(nil) } })) { request in
                    ForwardTargetsScreen(repository: composition.repositories.conversations, account: request.account, excluding: request.conversation,
                                         onPick: { composition.forwardChosen($0) }, onCancel: { composition.forwardChosen(nil) })
                }
                .onAppear { composition.permissions.send(phase == .active ? .foreground : .sceneInactive); composition.startPreferences(); coordinator.send(phase == .active ? .appeared : .sceneInactive) }
                .onDisappear { coordinator.send(.disappeared) }
                .onOpenURL { coordinator.send(.deepLink($0)) }
                .onChange(of: coordinator.viewModel.state.session) { _, session in composition.sessionChanged(session) }
                .onChange(of: phase) { _, phase in
                    switch phase {
                    case .active: composition.notifier.setActive(true); composition.permissions.send(.foreground); composition.startPreferences(); coordinator.send(.sceneActive)
                    case .inactive: composition.notifier.setActive(false); composition.permissions.send(.sceneInactive); coordinator.send(.sceneInactive)
                    case .background: composition.notifier.setActive(false); composition.permissions.send(.sceneInactive); runtime.enterBackground(coordinator)
                    @unknown default: composition.notifier.setActive(false); composition.permissions.send(.sceneInactive); coordinator.send(.sceneInactive)
                    }
                }
        }
    }
}
