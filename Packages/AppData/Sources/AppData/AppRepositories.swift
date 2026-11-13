// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct AppRepositories: Sendable {
    public let conversations: any ConversationsRepository
    public let session: any SessionRepository
    public let nodes: any NodeRepository
    public let onboarding: any OnboardingRepository
    public init(session: any SessionRepository, nodes: any NodeRepository, onboarding: any OnboardingRepository, conversations: any ConversationsRepository = UnavailableConversationsRepository()) {
        self.session = session; self.nodes = nodes; self.onboarding = onboarding; self.conversations = conversations
    }
}
