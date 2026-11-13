// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct AppRepositories: Sendable {
    public let chat: any ChatRepository
    public let conversations: any ConversationsRepository
    public let session: any SessionRepository
    public let nodes: any NodeRepository
    public let onboarding: any OnboardingRepository
    public init(session: any SessionRepository, nodes: any NodeRepository, onboarding: any OnboardingRepository, conversations: any ConversationsRepository = UnavailableConversationsRepository(), chat: any ChatRepository = UnavailableChatRepository()) {
        self.session = session; self.nodes = nodes; self.onboarding = onboarding; self.conversations = conversations; self.chat = chat
    }
}
