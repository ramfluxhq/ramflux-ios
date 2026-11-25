// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct AppRepositories: Sendable {
    public let cards: any CardsRepository
    public let tasks: any TasksRepository
    public let agents: any AgentsRepository
    /// Account lifecycle handlers (lock, removal) for account-scoped stores; shared with the repositories that trigger them.
    public let lifecycle: AccountLifecycleHooks
    public let pushRoutes: any PushRouteRepository
    public let delivery: any DeliveryRepository
    public let calls: any CallsRepository
    public let microphone: any MicrophoneRepository
    public let groups: any GroupsRepository
    public let settings: any SettingsRepository
    public let backup: any BackupRepository
    public let pairing: any PairingRepository
    public let preferences: any PreferencesRepository
    public let contacts: any ContactsRepository
    public let chat: any ChatRepository
    public let conversations: any ConversationsRepository
    public let session: any SessionRepository
    public let nodes: any NodeRepository
    public let onboarding: any OnboardingRepository
    /// Accounts created or restored on this device (public facts only), for unlock and account switch.
    public init(session: any SessionRepository, nodes: any NodeRepository, onboarding: any OnboardingRepository, conversations: any ConversationsRepository = UnavailableConversationsRepository(), chat: any ChatRepository = UnavailableChatRepository(), contacts: any ContactsRepository = UnavailableContactsRepository(), settings: any SettingsRepository = UnavailableSettingsRepository(), backup: any BackupRepository = UnavailableBackupRepository(), pairing: any PairingRepository = UnavailablePairingRepository(), preferences: any PreferencesRepository = NativePreferencesRepository(), groups: any GroupsRepository = UnavailableGroupsRepository(), calls: any CallsRepository = UnavailableCallsRepository(), microphone: any MicrophoneRepository = NativeMicrophoneRepository(), agents: any AgentsRepository = UnavailableAgentsRepository(), tasks: any TasksRepository = UnavailableTasksRepository(), cards: any CardsRepository = UnavailableCardsRepository(), lifecycle: AccountLifecycleHooks = AccountLifecycleHooks(), pushRoutes: any PushRouteRepository = UnavailablePushRouteRepository(), delivery: any DeliveryRepository = NativeDeliverySignalsRepository()) {
        self.lifecycle = lifecycle; self.pushRoutes = pushRoutes; self.delivery = delivery
        self.session = session; self.nodes = nodes; self.onboarding = onboarding; self.conversations = conversations; self.chat = chat; self.contacts = contacts; self.settings = settings; self.backup = backup; self.pairing = pairing; self.preferences = preferences; self.groups = groups; self.calls = calls; self.microphone = microphone; self.agents = agents; self.tasks = tasks; self.cards = cards
    }
}
