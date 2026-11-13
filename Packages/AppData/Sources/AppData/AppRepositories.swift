// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct AppRepositories: Sendable {
    public let groups: any GroupsRepository
    public let settings: any SettingsRepository
    public let backup: any BackupRepository
    public let preferences: any PreferencesRepository
    public let contacts: any ContactsRepository
    public let chat: any ChatRepository
    public let conversations: any ConversationsRepository
    public let session: any SessionRepository
    public let nodes: any NodeRepository
    public let onboarding: any OnboardingRepository
    public init(session: any SessionRepository, nodes: any NodeRepository, onboarding: any OnboardingRepository, conversations: any ConversationsRepository = UnavailableConversationsRepository(), chat: any ChatRepository = UnavailableChatRepository(), contacts: any ContactsRepository = UnavailableContactsRepository(), settings: any SettingsRepository = UnavailableSettingsRepository(), backup: any BackupRepository = UnavailableBackupRepository(), preferences: any PreferencesRepository = NativePreferencesRepository(), groups: any GroupsRepository = UnavailableGroupsRepository()) {
        self.session = session; self.nodes = nodes; self.onboarding = onboarding; self.conversations = conversations; self.chat = chat; self.contacts = contacts; self.settings = settings; self.backup = backup; self.preferences = preferences; self.groups = groups
    }
}
