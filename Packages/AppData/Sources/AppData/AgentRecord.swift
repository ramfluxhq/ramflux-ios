// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// An agent of this account as `agent.list` and `agent.get` return it (protocol `AgentRecord`).
public struct AgentRecord: Identifiable, Equatable, Sendable {
    /// The agent anchor: the stable SDK id.
    public let id: String
    public let persona: AgentPersona
    public let lifecycle: String
    public let role: String
    public let access: AgentAccess
    public init(id: String, persona: AgentPersona, lifecycle: String, role: String, access: AgentAccess) {
        self.id = id; self.persona = persona; self.lifecycle = lifecycle; self.role = role; self.access = access
    }
}
/// Peer-controlled display facts of an agent (protocol `AgentPersona`).
public struct AgentPersona: Equatable, Sendable {
    public var name: String
    public var avatar: String
    public var responsibility: String
    public init(name: String, avatar: String, responsibility: String) { self.name = name; self.avatar = avatar; self.responsibility = responsibility }
}
/// Who may reach the agent (protocol `AgentAccessPolicy`).
public struct AgentAccess: Equatable, Sendable {
    public let dm: String
    public let groupInviters: String
    public let allowedHumans: [String]
    public init(dm: String, groupInviters: String, allowedHumans: [String]) { self.dm = dm; self.groupInviters = groupInviters; self.allowedHumans = allowedHumans }
}
/// One page of agents plus the journal cursor `agent.watch` continues from.
public struct AgentPage: Equatable, Sendable {
    public let page: RowPage<AgentRecord>
    public let journalCursor: String
    public init(page: RowPage<AgentRecord>, journalCursor: String) { self.page = page; self.journalCursor = journalCursor }
}
/// A desktop-started agent creation waiting for this account's decision (protocol `AgentCustodyStatus`).
public struct AgentCreationRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let state: String
    public let agentAnchor: String?
    /// Unix seconds.
    public let expiresAt: Int64?
    public let failureReason: String?
    public init(id: String, state: String, agentAnchor: String?, expiresAt: Int64?, failureReason: String?) {
        self.id = id; self.state = state; self.agentAnchor = agentAnchor; self.expiresAt = expiresAt; self.failureReason = failureReason
    }
}
/// Agent capabilities the pinned SDK does not offer to this phone.
public enum AgentUnavailable: String, Equatable, Sendable, CaseIterable {
    /// `agent.access.set` needs the record's event identity as `base`; `agent.list`/`agent.get` do not return it.
    case access
    /// `agent.creation.decide` needs `request_hash`, computed from the plan bytes by Rust code the C ABI does not expose.
    case creationDecision
    /// The agent anchor is not a root anchor, so no direct conversation id can be derived for it.
    case chat
    /// No SDK methods: pausing, hiding and goal settings.
    case pause, hide, goal
}
