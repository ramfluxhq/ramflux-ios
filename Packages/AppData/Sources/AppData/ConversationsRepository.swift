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
            let body = try await gateway.call(.conversationDirectory, account: account)
            let records = try ProxyGateway.rows(body, "conversations").compactMap { row -> ConversationRecord? in
                if row["archived"] == .bool(true) || row["hidden"] == .bool(true) { return nil }
                let id = try ProxyGateway.text(row, "id")
                let title = row["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? id
                return ConversationRecord(id: id, title: title, preview: "", lastActivity: ProxyGateway.integer(row["last_activity"]), unreadCount: Self.count(row["unread_count"]))
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }; return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    private static func count(_ value: JSONValue?) -> UInt? {
        switch value {
        case .number(let number): number >= 0 ? UInt(exactly: number) : nil
        case .unsigned(let number): UInt(exactly: number)
        default: nil
        }
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
