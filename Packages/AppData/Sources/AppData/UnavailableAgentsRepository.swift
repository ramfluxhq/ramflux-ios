// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// Agent configuration is absent in the pinned SDK. Bot installation is a different domain.
public struct UnavailableAgentsRepository: AgentsRepository {
    public init() {}
    public func availability(account: String, capability: AgentCapability) async -> RepositoryResult<Void> { .failure(.unavailableResource("agents.unavailable")) }
    public func create(account: String, draft: AgentDraft) async -> RepositoryResult<String> { .failure(.unavailableResource("agents.unavailable")) }
}
