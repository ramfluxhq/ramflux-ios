// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct AgentEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String
    public var icon: String
    public init(id: String, name: String, detail: String, icon: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.icon = icon
    }
}

public struct AgentsState: Equatable, Sendable {
    public var mode: AgentCapability = .directory
    public var draft = AgentDraft()
    public var draftIssue: AgentDraftIssue?
    public var loading = false
    public var failure: AppFailure?
    /// Display-only directory rows. The live model leaves this empty.
    public var entries: [AgentEntry] = []
    public init(mode: AgentCapability = .directory) { self.mode = mode }
}
