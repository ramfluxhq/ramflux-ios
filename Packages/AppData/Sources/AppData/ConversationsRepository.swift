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
    private let peers: PeerClassifications?
    public init(client: RamfluxClient, updates: NativeUpdateSource, contacts: (any ContactsRepository)? = nil) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates; peers = contacts.map(PeerClassifications.init)
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
                guard seen.insert(try ProxyGateway.text(row, "id")).inserted else { EventDiagnostics.note("conversation.directory duplicate row id"); throw AppFailure.invalidData }
            }
            let visible = rows.filter { $0["archived"] != .bool(true) && $0["hidden"] != .bool(true) }
            // Direct rows carry the peer and its name from the SDK (`peer_principal_id`, `peer_display_name`);
            // the peer's verified kind comes from contacts in one lookup per page.
            let wanted = Set(visible.compactMap { Self.peer($0) })
            let known = wanted.isEmpty ? [:] : await peers?.entries(account: account, wanted: wanted) ?? [:]
            let records = try visible.map { row -> ConversationRecord in
                let id = try ProxyGateway.text(row, "id")
                let group = row["group_id"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                var title = row["title"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                var identifier = false
                let peer = group == nil ? Self.peer(row) : nil
                if title == nil, group == nil {
                    title = row["peer_display_name"]?.string.flatMap { $0.isEmpty || $0.utf8.count > 1024 ? nil : $0 } ?? peer.flatMap { known[$0]?.name }
                    if title == nil { title = peer.map(Self.shortIdentifier) ?? id; identifier = true }
                }
                return ConversationRecord(id: id, title: title ?? id, preview: "", lastActivity: ProxyGateway.integer(row["last_activity"]), unreadCount: Self.count(row["unread_count"]),
                                          kind: group == nil ? "person" : "group", muted: row["muted"] == .bool(true), groupID: group, titleIsIdentifier: identifier,
                                          classification: peer.flatMap { known[$0]?.classification } ?? .unknown, peer: peer)
            }
            let next: String?
            switch body["next_cursor"] {
            case .string(let value) where !value.isEmpty: next = value
            case .null, nil: next = nil
            default: EventDiagnostics.note("conversation.directory next_cursor is not a string"); throw AppFailure.invalidData
            }
            return .success(ConversationPage(rows: records, nextCursor: next))
        } catch { EventDiagnostics.failed("conversation.directory", error); return .failure(AppFailure.map(error)) }
    }
    public func pendingRequests(account: String) async -> RepositoryResult<UInt> {
        do {
            let rows = try ProxyGateway.rows(try await gateway.call(.contactRequestsList, account: account), "requests")
            return .success(UInt(rows.filter { $0["direction"]?.string == "inbound" && $0["state"]?.string == "pending" }.count))
        } catch { EventDiagnostics.failed("contact.requests.list", error); return .failure(AppFailure.map(error)) }
    }
    /// The peer of a direct row as the SDK names it (`peer_principal_id`). A conversation that began with
    /// an inbound message has no direct route yet and the SDK omits the peer fields; its participants
    /// other than this account name the peer then, and its contact name titles the row.
    static func peer(_ row: JSONValue) -> String? {
        guard row["group_id"]?.string?.isEmpty ?? true else { return nil }
        if let peer = row["peer_principal_id"]?.string, !peer.isEmpty, peer.utf8.count <= 2048 { return peer }
        let me = row["self_principal_id"]?.string
        guard case .array(let participants)? = row["participants"] else { return nil }
        return participants.prefix(8).compactMap(\.string).first { !$0.isEmpty && $0 != me && $0.utf8.count <= 2048 }
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
