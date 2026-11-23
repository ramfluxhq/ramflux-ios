// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public protocol AgentsRepository: Sendable {
    /// One page of this account's agents (`agent.list`, cursor `next`).
    func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<AgentPage>
    func record(account: String, agent: String) async -> RepositoryResult<AgentRecord>
    /// Records changed since `journalCursor` (`agent.watch`), for patching a held window by id.
    func changes(account: String, since journalCursor: String) async -> RepositoryResult<AgentPage>
    func editPersona(account: String, agent: String, persona: AgentPersona) async -> RepositoryResult<AgentRecord>
    func delete(account: String, agent: String) async -> RepositoryResult<AgentRecord>
    /// The pending desktop-started creation, if any (`agent.operation.get` with an empty id).
    func pendingCreation(account: String) async -> RepositoryResult<AgentCreationRequest?>
    /// The direct conversation with an agent: the SDK's DM scope of this account's root
    /// (`account.status` `principal_commitment`) and the agent anchor, not the anchor itself.
    func chatConversation(account: String, agent: String) async -> RepositoryResult<String>
    func observe(account: String) async -> RepositoryObservation
    func unavailable(_ capability: AgentUnavailable) -> AppFailure
}
public struct NativeAgentsRepository: AgentsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<AgentPage> {
        var fields: [String: JSONValue] = ["limit": .number(Double(min(max(limit, 1), 100)))]
        if let cursor { fields["cursor"] = .string(cursor) }
        let body = JSONValue.object(fields)
        return await read { try Self.page(await gateway.call(.agentList, account: account, body: body)) }
    }
    public func record(account: String, agent: String) async -> RepositoryResult<AgentRecord> {
        await read { try Self.record(await gateway.call(.agentGet, account: account, body: .object(["agent_anchor": .string(agent)]))["record"]) }
    }
    public func changes(account: String, since journalCursor: String) async -> RepositoryResult<AgentPage> {
        await read { try Self.page(await gateway.call(.agentWatch, account: account, body: .object(["journal_cursor": .string(journalCursor)]))) }
    }
    public func editPersona(account: String, agent: String, persona: AgentPersona) async -> RepositoryResult<AgentRecord> {
        let name = persona.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 256, persona.responsibility.utf8.count <= 4096, persona.avatar.utf8.count <= 2048 else { return .failure(.invalidInput) }
        let body: JSONValue = .object(["agent_anchor": .string(agent), "confirmed": .bool(true),
            "persona": .object(["name": .string(name), "avatar": .string(persona.avatar), "responsibility": .string(persona.responsibility)])])
        return await read { try Self.record(await gateway.call(.agentPersonaEdit, account: account, body: body)["record"]) }
    }
    public func delete(account: String, agent: String) async -> RepositoryResult<AgentRecord> {
        await read { try Self.record(await gateway.call(.agentDelete, account: account, body: .object(["agent_anchor": .string(agent), "confirmed": .bool(true)]))["record"]) }
    }
    public func pendingCreation(account: String) async -> RepositoryResult<AgentCreationRequest?> {
        await read {
            guard let status = try await gateway.call(.agentOperationGet, account: account, body: .object(["operation_id": .string("")]))["custody"] else { return nil }
            return AgentCreationRequest(id: try ProxyGateway.text(status, "requestId"), state: try ProxyGateway.text(status, "state"), agentAnchor: status["agentAnchor"]?.string,
                                        expiresAt: ProxyGateway.integer(status["expiresAt"]), failureReason: status["error"]?["reasonCode"]?.string)
        }
    }
    public func chatConversation(account: String, agent: String) async -> RepositoryResult<String> {
        do {
            guard let id = try await DirectConversationID.resolve(gateway, account: account, peer: agent) else { return .failure(unavailable(.chat)) }
            return .success(id)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    public func unavailable(_ capability: AgentUnavailable) -> AppFailure { .unavailableResource("agents.unavailable." + capability.rawValue) }
    private func read<Value: Sendable>(_ body: @Sendable () async throws -> Value) async -> RepositoryResult<Value> {
        do { return .success(try await body()) } catch { return .failure(AppFailure.map(error)) }
    }
    /// Maps `{"page": AgentPage}`; the SDK writes protocol JSON names (lower camel case).
    static func page(_ body: JSONValue) throws -> AgentPage {
        guard let page = body["page"] else { throw AppFailure.invalidData }
        let rows: [AgentRecord]
        if page["records"] == nil { rows = [] } else { rows = try ProxyGateway.rows(page, "records").map { try record($0) } }
        guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }
        return AgentPage(page: RowPage(rows: rows, nextCursor: page["next"]?.string), journalCursor: page["journalCursor"]?.string ?? "")
    }
    static func record(_ value: JSONValue?) throws -> AgentRecord {
        guard let value else { throw AppFailure.invalidData }
        let persona = value["persona"], access = value["access"]
        let humans: [String] = if case .array(let items) = access?["allowedHumans"] { items.compactMap(\.string) } else { [] }
        return AgentRecord(id: try ProxyGateway.text(value, "agentAnchor"),
                           persona: AgentPersona(name: persona?["name"]?.string ?? "", avatar: persona?["avatar"]?.string ?? "", responsibility: persona?["responsibility"]?.string ?? ""),
                           lifecycle: value["lifecycle"]?.string ?? "", role: value["role"]?.string ?? "",
                           access: AgentAccess(dm: access?["dm"]?.string ?? "", groupInviters: access?["groupInviters"]?.string ?? "", allowedHumans: humans))
    }
}
public struct UnavailableAgentsRepository: AgentsRepository {
    public init() {}
    public func chatConversation(account: String, agent: String) async -> RepositoryResult<String> { .failure(.sdkUnavailable) }
    public func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<AgentPage> { .failure(.sdkUnavailable) }
    public func record(account: String, agent: String) async -> RepositoryResult<AgentRecord> { .failure(.sdkUnavailable) }
    public func changes(account: String, since journalCursor: String) async -> RepositoryResult<AgentPage> { .failure(.sdkUnavailable) }
    public func editPersona(account: String, agent: String, persona: AgentPersona) async -> RepositoryResult<AgentRecord> { .failure(.sdkUnavailable) }
    public func delete(account: String, agent: String) async -> RepositoryResult<AgentRecord> { .failure(.sdkUnavailable) }
    public func pendingCreation(account: String) async -> RepositoryResult<AgentCreationRequest?> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
    public func unavailable(_ capability: AgentUnavailable) -> AppFailure { .unavailableResource("agents.unavailable." + capability.rawValue) }
}
