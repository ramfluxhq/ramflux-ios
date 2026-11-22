// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
/// One directory row projected from an `AgentRecord`.
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
public enum AgentsMode: Equatable, Sendable { case directory, profile(String), edit(String) }
public struct AgentsState: Equatable, Sendable {
    public var mode: AgentsMode = .directory
    public var loading = false
    public var loadingMore = false
    public var busy = false
    public var failure: AppFailure?
    /// Directory rows of the held window (at most a few hundred).
    public var entries: [AgentEntry] = []
    public var canLoadMore = false
    public var query = ""
    /// The agent of the profile and edit screens.
    public var selected: AgentRecord?
    public var draft = AgentPersona(name: "", avatar: "", responsibility: "")
    public var confirmingDelete = false
    public var confirmingEdit = false
    /// A desktop-started creation waiting for this account (shown above the directory).
    public var creation: AgentCreationRequest?
    public init(mode: AgentsMode = .directory) { self.mode = mode }
}
