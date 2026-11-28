// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public protocol ContactsRepository: Sendable {
    func pendingMutation(account: String) async -> PendingContactMutation?
    func contacts(account: String) async -> RepositoryResult<[ContactRecord]>
    func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]>
    func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void>
    func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void>
    /// Removes, blocks or unblocks an accepted contact.
    func change(account: String, contact: ContactRecord, change: ContactChange, operationID: String) async -> RepositoryResult<Void>
    /// One page of accepted contacts whose name or principal contains `query` (empty matches all).
    func contactsPage(account: String, query: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRecord>>
    /// One page of contact requests in one direction (`inbound` or `outbound`).
    func requestsPage(account: String, direction: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRequestRecord>>
    func observe(account: String) async -> RepositoryObservation
    func unavailable(_ capability: ContactUnavailable) -> AppFailure
    /// This account's signed contact card (`contact.card.export`): the text form and the link form.
    func ownCard(account: String) async -> RepositoryResult<ContactCardExport>
    /// Resolves `@name` in the username directory (`username.resolve`) before a contact request is sent to it.
    func resolveUsername(account: String, name: String) async -> RepositoryResult<UsernameResolution>
}
public extension ContactsRepository {
    func resolveUsername(account: String, name: String) async -> RepositoryResult<UsernameResolution> { .failure(.unsupported) }
}
/// A contact card of this account as the SDK exports it. Public: it names the account, its devices and its
/// home node so a peer can add it and reach it; it carries no secret.
public struct ContactCardExport: Equatable, Sendable {
    public let card: String
    public let link: String
    public init(card: String, link: String) { self.card = card; self.link = link }
}
public struct NativeContactsRepository: ContactsRepository {
    private let mutations = RetainedMutation<ContactMutationArguments, Void>()
    public func pendingMutation(account: String) async -> PendingContactMutation? {
        guard let entry = await mutations.snapshot(scope: account), entry.unresolved else { return nil }
        return PendingContactMutation(arguments: entry.arguments, operationID: entry.operationID)
    }
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    // `contact.list` and `contact.requests.list` are unpaged in the SDK; these page their snapshots.
    private let contactPager = SnapshotPager<ContactRecord>()
    private let requestPager = SnapshotPager<ContactRequestRecord>()
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func contactsPage(account: String, query: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRecord>> {
        let query = String(query.prefix(256))
        return await contactPager.page(cursor: cursor, limit: limit, read: { await self.contacts(account: account) }, include: { ContactRecord.matches($0, query) })
    }
    public func requestsPage(account: String, direction: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRequestRecord>> {
        await requestPager.page(cursor: cursor, limit: limit, read: { await self.requests(account: account) }, include: { $0.direction == direction })
    }
    public func change(account: String, contact: ContactRecord, change: ContactChange, operationID: String) async -> RepositoryResult<Void> {
        guard let link = contact.linkID else { return .failure(.invalidInput) }
        let (operation, body): (SDKOperation, JSONValue) = switch change {
        case .remove: (.contactRemove, .object(["link_id": .string(link), "scope": .string("me")]))
        case .block: (.contactBlock, .object(["link_id": .string(link)]))
        default: (.contactUnblock, .object(["link_id": .string(link)]))
        }
        return await mutations.run(scope: account, arguments: .change(contact.id, change), operationID: operationID) { [gateway] in
            do { _ = try await gateway.call(operation, account: account, body: body, operationID: operationID); return .success(()) }
            catch { return .failure(AppFailure.map(error)) }
        }
    }
    public func contacts(account: String) async -> RepositoryResult<[ContactRecord]> {
        do {
            let body = try await gateway.call(.contactList, account: account)
            let records = try await ProxyGateway.mapRows(body, "contacts") { row in
                let id = try ProxyGateway.text(row, "principal_id")
                return ContactRecord(id: id, displayName: row["display_name"]?.string ?? id, subtitle: id, rootCommitment: row["root_commitment"]?.string,
                                     linkID: row["link_id"]?.string, blocked: row["blocked"]?.bool ?? false, classification: PrincipalClassification(sdk: row["verified_classification"]))
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }; return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]> {
        do {
            let body = try await gateway.call(.contactRequestsList, account: account)
            let records = try await ProxyGateway.mapRows(body, "requests") { row in
                let principal = try ProxyGateway.text(row, "principal_id")
                return ContactRequestRecord(id: try ProxyGateway.text(row, "request_id"), principal: principal, name: row["display_name"]?.string ?? principal,
                    direction: try ProxyGateway.text(row, "direction"), state: try ProxyGateway.text(row, "state"), preview: row["preview"]?.string, classification: PrincipalClassification(sdk: row["verified_classification"]))
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }; return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> {
        let value = principal.trimmingCharacters(in: .whitespacesAndNewlines)
        // A contact card (text or link form) names the peer's devices and home node; a principal id alone
        // leaves the contact without a pinned home node, so attachments to it fail with authority_unavailable.
        let card = Self.isCard(value)
        guard !value.isEmpty, value.utf8.count <= (card ? 64 * 1024 : 2048) else { return .failure(.invalidInput) }
        // "@name" adds by username through the username directory (`username.contact.add`); the screen resolves it first.
        if !card, value.hasPrefix("@") {
            guard let name = UsernameInput.name(value) else { return .failure(.invalidInput) }
            return await mutations.run(scope: account, arguments: .add(value), operationID: operationID) { [gateway] in
                do { _ = try await gateway.call(.usernameContactAdd, account: account, body: .object(["name": .string(name)]), operationID: operationID); return .success(()) }
                catch { EventDiagnostics.failed("username.contact.add", error); return .failure(AppFailure.mapUsername(error)) }
            }
        }
        let body: JSONValue = .object(card ? ["card": .string(value)] : ["principal_id": .string(value)])
        return await mutations.run(scope: account, arguments: .add(value), operationID: operationID) { [gateway] in
        do { _ = try await gateway.call(.contactAdd, account: account, body: body, operationID: operationID); return .success(()) }
        catch { EventDiagnostics.failed("contact.add", error); return .failure(AppFailure.map(error)) }
        }
    }
    public func resolveUsername(account: String, name: String) async -> RepositoryResult<UsernameResolution> {
        guard let query = UsernameInput.name(name) else { return .failure(.invalidInput) }
        do {
            let body = try await gateway.call(.usernameResolve, account: account, body: .object(["name": .string(query)]))
            return .success(try UsernameResolution.parse(body, query: query))
        } catch { EventDiagnostics.failed("username.resolve", error); return .failure(AppFailure.mapUsername(error)) }
    }
    /// Whether the add-contact input is a contact card (`ramflux-card:` text or a `ramflux://contact/` link).
    static func isCard(_ value: String) -> Bool { value.hasPrefix("ramflux-card:") || value.hasPrefix("ramflux://contact/") }
    public func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void> {
        let operation: SDKOperation = switch decision { case .accept: .contactAccept; case .decline: .contactDecline; case .block: .contactBlock }
        return await mutations.run(scope: account, arguments: .decide(request, decision), operationID: operationID) { [gateway] in
        do { _ = try await gateway.call(operation, account: account, body: .object(["request_id": .string(request)]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
        }
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    public func ownCard(account: String) async -> RepositoryResult<ContactCardExport> {
        do {
            let body = try await gateway.call(.contactCardExport, account: account)
            let card = try ProxyGateway.text(body, "card"), link = try ProxyGateway.text(body, "link")
            guard card.utf8.count <= 64 * 1024, link.utf8.count <= 64 * 1024 else { throw AppFailure.invalidData }
            return .success(ContactCardExport(card: card, link: link))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func unavailable(_ capability: ContactUnavailable) -> AppFailure { Self.refusal(capability) }
    static func refusal(_ capability: ContactUnavailable) -> AppFailure {
        switch capability {
        case .reporting: .unavailableResource("contacts.unavailable.reporting")
        case .batch: .unavailableResource("contacts.unavailable.batch")
        case .replyWithoutAcceptance: .unavailableResource("contacts.unavailable.replyWithoutAcceptance")
        }
    }
}
public struct UnavailableContactsRepository: ContactsRepository {
    public init() {}
    public func contacts(account: String) async -> RepositoryResult<[ContactRecord]> { .failure(.sdkUnavailable) }
    public func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]> { .failure(.sdkUnavailable) }
    public func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
    public func unavailable(_ capability: ContactUnavailable) -> AppFailure { NativeContactsRepository.refusal(capability) }
}

public extension ContactsRepository {
    func pendingMutation(account: String) async -> PendingContactMutation? { nil }
    func ownCard(account: String) async -> RepositoryResult<ContactCardExport> { .failure(.unsupported) }
    func change(account: String, contact: ContactRecord, change: ContactChange, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    /// Stateless fallback for repositories without a pager: re-reads the list and pages it by offset.
    func contactsPage(account: String, query: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRecord>> {
        switch await contacts(account: account) {
        case .failure(let failure): return .failure(failure)
        case .success(let rows): return .success(Self.offsetPage(rows.filter { ContactRecord.matches($0, query) }, cursor: cursor, limit: limit))
        }
    }
    func requestsPage(account: String, direction: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRequestRecord>> {
        switch await requests(account: account) {
        case .failure(let failure): return .failure(failure)
        case .success(let rows): return .success(Self.offsetPage(rows.filter { $0.direction == direction }, cursor: cursor, limit: limit))
        }
    }
    /// One accepted contact by principal id (`nil` when it is not a contact). `contact.list` has no
    /// single-row read, so this reads the list in the data layer.
    func contact(account: String, id: String) async -> RepositoryResult<ContactRecord?> {
        switch await contacts(account: account) { case .failure(let failure): .failure(failure); case .success(let rows): .success(rows.first { $0.id == id }) }
    }
    /// One contact request by id (`nil` when it no longer exists).
    func request(account: String, id: String) async -> RepositoryResult<ContactRequestRecord?> {
        switch await requests(account: account) { case .failure(let failure): .failure(failure); case .success(let rows): .success(rows.first { $0.id == id }) }
    }
    static func offsetPage<Row>(_ rows: [Row], cursor: String?, limit: Int) -> RowPage<Row> {
        let start = min(cursor.flatMap(Int.init) ?? 0, rows.count), end = min(start + max(1, limit), rows.count)
        return RowPage(rows: Array(rows[start..<end]), nextCursor: end < rows.count ? String(end) : nil)
    }
}
public extension ContactRecord {
    /// Case-insensitive match of the display name or principal id; an empty query matches every contact.
    static func matches(_ contact: ContactRecord, _ query: String) -> Bool {
        query.isEmpty || contact.displayName.localizedCaseInsensitiveContains(query) || contact.id.localizedCaseInsensitiveContains(query)
    }
}
