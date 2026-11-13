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
import FeatureCards
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
                if tab == .messages, let account { return AnyView(ConversationsHost(coordinator: composition.conversations(account: account))) }
                if tab == .groups, let account { return AnyView(GroupsHost(coordinator: composition.groups(account: account))) }
                if tab == .agents, let account { return AnyView(AgentsHost(coordinator: composition.agents(account: account))) }
                if tab == .more { return AnyView(SettingsHost(coordinator: composition.settings(account: account, route: .settings))) }
                return nil
            }) { route in
                switch route {
                case .cards: return AnyView(CardsHost(coordinator: composition.cards))
                case .tasks, .permissions:
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(TasksHost(coordinator: composition.tasks(account: account, permissions: route == .permissions))) }
                    else { return AnyView(RFUnavailableView(title: RamfluxAppStrings.text("copy.3601da87db9d"), message: RamfluxAppStrings.text("copy.ca69b8b49dd0"))) }
                case .calls(let conversation):
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(CallsHost(coordinator: composition.calls(account: account, conversation: conversation))) }
                    else { return AnyView(RFUnavailableView(title: RamfluxAppStrings.text("copy.3601da87db9d"), message: RamfluxAppStrings.text("copy.ca69b8b49dd0"))) }
                case .groupConversation(let id, let title):
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(ChatHost(coordinator: composition.chat(account: account, conversation: id, isGroup: true, title: title))) }
                    else { return AnyView(RFUnavailableView(title: RamfluxAppStrings.text("copy.3601da87db9d"), message: RamfluxAppStrings.text("copy.ca69b8b49dd0"))) }
                case .conversation(let id):
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(ChatHost(coordinator: composition.chat(account: account, conversation: id))) }
                    else { return AnyView(RFUnavailableView(title: RamfluxAppStrings.text("copy.3601da87db9d"), message: RamfluxAppStrings.text("copy.ca69b8b49dd0"))) }
                case .contacts, .strangers, .contact, .safetyNumber:
                    if let account = coordinator.viewModel.state.session.activeAccountID {
                        let mode: ContactsMode = switch route { case .strangers: .strangers; case .contact(let id): .profile(id); case .safetyNumber(let id): .safety(id); default: .contacts }
                        return AnyView(ContactsHost(coordinator: composition.contacts(account: account, mode: mode)))
                    } else { return AnyView(RFUnavailableView(title: RamfluxAppStrings.text("copy.3601da87db9d"), message: RamfluxAppStrings.text("copy.8a07f13cdb0d"))) }
                case .onboarding, .recoverAccount, .linkDevice: return AnyView(OnboardingHost(coordinator: composition.onboarding))
                default: return AnyView(SettingsHost(coordinator: composition.settings(account: coordinator.viewModel.state.session.activeAccountID, route: route)))
                }
            }
            }
                .onAppear { composition.startPreferences(); coordinator.send(phase == .active ? .appeared : .sceneInactive) }
                .onDisappear { coordinator.send(.disappeared) }
                .onOpenURL { coordinator.send(.deepLink($0)) }
                .onChange(of: phase) { _, phase in
                    switch phase {
                    case .active: composition.startPreferences(); coordinator.send(.sceneActive)
                    case .inactive: coordinator.send(.sceneInactive)
                    case .background: runtime.enterBackground(coordinator)
                    @unknown default: coordinator.send(.sceneInactive)
                    }
                }
        }
    }
}
