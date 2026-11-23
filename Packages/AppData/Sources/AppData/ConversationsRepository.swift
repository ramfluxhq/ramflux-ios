// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RamfluxCore
/// One page of the conversation directory. `nextCursor` is the SDK's opaque cursor; nil means the end.
public struct ConversationPage: Sendable, Equatable {
    public let rows: [ConversationRecord]
    public let nextCursor: String?
    public init(rows: [ConversationRecord], nextCursor: String?) { self.rows = rows; self.nextCursor = nextCursor }
}
public protocol ConversationsRepository: Sendable {
    /// Reads one directory page after `cursor`. The SDK orders pages by conversation id, not by activity.
    func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<ConversationPage>
    /// Number of inbound contact requests still pending (the "message requests" row).
    func pendingRequests(account: String) async -> RepositoryResult<UInt>
    func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]>
    func observe(account: String) async -> RepositoryObservation
}
public struct NativeConversationsRepository: ConversationsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public static let pageLimit = 50
    public func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<ConversationPage> {
        do {
            var request: [String: JSONValue] = ["limit": .number(Double(min(max(limit, 1), 100)))]
            if let cursor { request["cursor"] = .string(cursor) }
            let body = try await gateway.call(.conversationDirectory, account: account, body: .object(request))
            let rows = try ProxyGateway.rows(body, "conversations")
            var seen = Set<String>()
            for row in rows {
                guard seen.insert(try ProxyGateway.text(row, "id")).inserted else { throw AppFailure.invalidData }
            }
            let records = try rows.compactMap { row -> ConversationRecord? in
                if row["archived"] == .bool(true) || row["hidden"] == .bool(true) { return nil }
                let id = try ProxyGateway.text(row, "id")
                let title = row["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? id
                let group = row["group_id"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                return ConversationRecord(id: id, title: title, preview: "", lastActivity: ProxyGateway.integer(row["last_activity"]), unreadCount: Self.count(row["unread_count"]), kind: group == nil ? "person" : "group", muted: row["muted"] == .bool(true), groupID: group)
            }
            let next: String?
            switch body["next_cursor"] {
            case .string(let value) where !value.isEmpty: next = value
            case .null, nil: next = nil
            default: throw AppFailure.invalidData
            }
            return .success(ConversationPage(rows: records, nextCursor: next))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func pendingRequests(account: String) async -> RepositoryResult<UInt> {
        do {
            let rows = try ProxyGateway.rows(try await gateway.call(.contactRequestsList, account: account), "requests")
            return .success(UInt(rows.filter { $0["direction"]?.string == "inbound" && $0["state"]?.string == "pending" }.count))
        } catch { return .failure(AppFailure.map(error)) }
    }
    private static func count(_ value: JSONValue?) -> UInt? {
        switch value {
        case .number(let number): number >= 0 ? UInt(exactly: number) : nil
        case .unsigned(let number): UInt(exactly: number)
        default: nil
        }
    }
    public func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]> { .failure(.unavailableResource("conversations.unavailable.searchService")) }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
}
public struct UnavailableConversationsRepository: ConversationsRepository {
    public init() {}
    public func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<ConversationPage> { .failure(.sdkUnavailable) }
    public func pendingRequests(account: String) async -> RepositoryResult<UInt> { .failure(.sdkUnavailable) }
    public func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]> { .failure(.unavailableResource("conversations.unavailable.search")) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}
