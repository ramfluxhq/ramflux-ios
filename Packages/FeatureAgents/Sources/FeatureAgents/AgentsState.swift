// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct AgentsState: Equatable, Sendable {
    public var mode: AgentCapability = .directory
    public var draft = AgentDraft()
    public var draftIssue: AgentDraftIssue?
    public var loading = false
    public var failure: AppFailure?
    public init(mode: AgentCapability = .directory) { self.mode = mode }
}
