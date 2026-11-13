// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
import FeatureAppShell
import FeatureOnboarding
import FeatureConversations
import FeatureChat
import FeatureContacts
@MainActor final class AppComposition {
    let repositories: AppRepositories
    let shell: AppShellCoordinator
    lazy var onboarding = OnboardingCoordinator(repository: repositories.onboarding, nodes: repositories.nodes) { [weak self] account in
        self?.shell.path = []
        if account != nil { self?.shell.send(.retry) }
    }
    private var inbox: (String, ConversationsCoordinator)?
    func conversations(account: String) -> ConversationsCoordinator {
        if let inbox, inbox.0 == account { return inbox.1 }
        inbox?.1.send(.disappeared)
        let coordinator = ConversationsCoordinator(repository: repositories.conversations, account: account) { [weak self] route in self?.shell.send(.open(route)) }
        inbox = (account, coordinator); return coordinator
    }
    private var currentChat: (String, String, ChatCoordinator)?
    func chat(account: String, conversation: String) -> ChatCoordinator {
        if let currentChat, currentChat.0 == account, currentChat.1 == conversation { return currentChat.2 }
        currentChat?.2.send(.disappeared)
        let coordinator = ChatCoordinator(repository: repositories.chat, account: account, conversation: conversation)
        currentChat = (account, conversation, coordinator); return coordinator
    }
    private var currentContacts: (String, ContactsMode, ContactsCoordinator)?
    func contacts(account: String, mode: ContactsMode) -> ContactsCoordinator {
        if let currentContacts, currentContacts.0 == account, currentContacts.1 == mode { return currentContacts.2 }
        currentContacts?.2.send(.disappeared)
        let coordinator = ContactsCoordinator(repository: repositories.contacts, account: account, mode: mode) { [weak self] route in self?.shell.send(.open(route)) }
        currentContacts = (account, mode, coordinator); return coordinator
    }
    init() { let repositories = AppDataFactory.repositories(); self.repositories = repositories; shell = AppShellCoordinator(repository: repositories.session) }
}
