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
    private let titles: DirectConversationTitles?
    public init(client: RamfluxClient, updates: NativeUpdateSource, contacts: (any ContactsRepository)? = nil) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates; titles = contacts.map(DirectConversationTitles.init)
    }
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
            let visible = rows.filter { $0["archived"] != .bool(true) && $0["hidden"] != .bool(true) }
            // Direct rows without an SDK title are named from contacts in one lookup per page.
            let peers = visible.compactMap { row -> [String]? in
                guard row["group_id"]?.string?.isEmpty ?? true, row["title"]?.string?.isEmpty ?? true else { return nil }
                return Self.directPeers(row)
            }
            let names = peers.isEmpty ? [:] : await titles?.names(account: account, wanted: Set(peers.joined())) ?? [:]
            let records = try visible.map { row -> ConversationRecord in
                let id = try ProxyGateway.text(row, "id")
                let group = row["group_id"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                var title = row["title"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                var identifier = false
                if title == nil, group == nil {
                    let keys = Self.directPeers(row)
                    title = keys.lazy.compactMap { names[$0] }.first
                    if title == nil { title = keys.first.map(Self.shortIdentifier) ?? id; identifier = true }
                }
                return ConversationRecord(id: id, title: title ?? id, preview: "", lastActivity: ProxyGateway.integer(row["last_activity"]), unreadCount: Self.count(row["unread_count"]),
                                          kind: group == nil ? "person" : "group", muted: row["muted"] == .bool(true), groupID: group, titleIsIdentifier: identifier)
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
    /// The peer of a direct row: the route's principal commitment, then the participants other than this account.
    static func directPeers(_ row: JSONValue) -> [String] {
        var keys: [String] = []
        if let commitment = row["direct_route"]?["recipient_principal_commitment"]?.string, !commitment.isEmpty { keys.append(commitment) }
        let me = row["self_principal_id"]?.string
        if case .array(let participants)? = row["participants"] {
            keys += participants.prefix(8).compactMap { $0.string }.filter { !$0.isEmpty && $0 != me }
        }
        return keys
    }
    /// A short form of an identifier for a row with no known name: the first characters after any
    /// `principal-` style prefix, left-to-right isolated like every identifier.
    static func shortIdentifier(_ value: String) -> String {
        let body = value.split(separator: "-", maxSplits: 1).count == 2 && value.hasPrefix("principal-") ? String(value.dropFirst("principal-".count)) : value
        let short = body.count > 12 ? String(body.prefix(10)) + "\u{2026}" : body
        return "\u{2066}" + short + "\u{2069}"
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
