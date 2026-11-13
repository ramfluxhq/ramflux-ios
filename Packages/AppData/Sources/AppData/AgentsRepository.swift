// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public protocol AgentsRepository: Sendable {
    func availability(account: String, capability: AgentCapability) async -> RepositoryResult<Void>
    func create(account: String, draft: AgentDraft) async -> RepositoryResult<String>
}
