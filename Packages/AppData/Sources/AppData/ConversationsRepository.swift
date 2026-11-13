// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RamfluxCore
public protocol ConversationsRepository: Sendable {
    func list(account: String) async -> RepositoryResult<[ConversationRecord]>
    func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]>
    func observe(account: String) async -> RepositoryObservation
}
public struct NativeConversationsRepository: ConversationsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func list(account: String) async -> RepositoryResult<[ConversationRecord]> {
        do {
            let body = try await gateway.call(.conversationList, account: account)
            let records = try ProxyGateway.rows(body, "conversations").filter { $0["is_archived"] != .bool(true) }.map { row in
                let id = try ProxyGateway.text(row, "conversation_id")
                return ConversationRecord(id: id, title: id, preview: "", lastActivity: ProxyGateway.integer(row["last_activity_at"]))
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }; return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]> { .failure(.unavailableResource("copy.6bf512f2eab9")) }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
}
public struct UnavailableConversationsRepository: ConversationsRepository {
    public init() {}
    public func list(account: String) async -> RepositoryResult<[ConversationRecord]> { .failure(.sdkUnavailable) }
    public func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]> { .failure(.unavailableResource("copy.61e1cb437dd3")) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}
