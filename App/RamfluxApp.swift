// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import FeatureAppShell
import AppData
import FeatureOnboarding
import FeatureConversations
import FeatureChat
import FeatureContacts
import RFDesign

@main struct RamfluxApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var runtime = AppLifecycleCoordinator()
    @State private var composition = AppComposition()
    private var coordinator: AppShellCoordinator { composition.shell }
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            AppShellHost(coordinator: coordinator, tabContent: { tab, account in
                if tab == .messages, let account { return AnyView(ConversationsHost(coordinator: composition.conversations(account: account))) }
                return nil
            }) { route in
                switch route {
                case .conversation(let id):
                    if let account = coordinator.viewModel.state.session.activeAccountID { return AnyView(ChatHost(coordinator: composition.chat(account: account, conversation: id))) }
                    else { return AnyView(RFUnavailableView(title: "Unlock your account", message: "Open this account before reading a conversation.")) }
                case .contacts, .strangers, .contact, .safetyNumber:
                    if let account = coordinator.viewModel.state.session.activeAccountID {
                        let mode: ContactsMode = switch route { case .strangers: .strangers; case .contact(let id): .profile(id); case .safetyNumber(let id): .safety(id); default: .contacts }
                        return AnyView(ContactsHost(coordinator: composition.contacts(account: account, mode: mode)))
                    } else { return AnyView(RFUnavailableView(title: "Unlock your account", message: "Open this account before reading contacts.")) }
                case .onboarding, .recoverAccount, .linkDevice: return AnyView(OnboardingHost(coordinator: composition.onboarding))
                default: return AnyView(RFUnavailableView(title: "Ramflux", message: UnavailableReason.featureNotInstalled.message))
                }
            }
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
                .onAppear { coordinator.send(phase == .active ? .appeared : .sceneInactive) }
                .onDisappear { coordinator.send(.disappeared) }
                .onOpenURL { coordinator.send(.deepLink($0)) }
                .onChange(of: phase) { _, phase in
                    switch phase {
                    case .active: coordinator.send(.sceneActive)
                    case .inactive: coordinator.send(.sceneInactive)
                    case .background: runtime.enterBackground(coordinator)
                    @unknown default: coordinator.send(.sceneInactive)
                    }
                }
        }
    }
}
