// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public protocol ContactsRepository: Sendable {
    func contacts(account: String) async -> RepositoryResult<[ContactRecord]>
    func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]>
    func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void>
    func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void>
    func safety(account: String, contact: ContactRecord) async -> RepositoryResult<ContactSafety>
    func observe(account: String) async -> RepositoryObservation
    func unavailable(_ capability: ContactUnavailable) -> AppFailure
}
public struct NativeContactsRepository: ContactsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func contacts(account: String) async -> RepositoryResult<[ContactRecord]> {
        do {
            let body = try await gateway.call(.contactList, account: account)
            let records = try ProxyGateway.rows(body, "contacts").map { row in
                let id = try ProxyGateway.text(row, "principal_id")
                return ContactRecord(id: id, displayName: row["display_name"]?.string ?? id, subtitle: id, verified: row["verified"]?.bool, rootCommitment: row["root_commitment"]?.string)
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }; return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]> {
        do {
            let body = try await gateway.call(.contactRequestsList, account: account)
            let records = try ProxyGateway.rows(body, "requests").map { row in
                let principal = try ProxyGateway.text(row, "principal_id")
                return ContactRequestRecord(id: try ProxyGateway.text(row, "request_id"), principal: principal, name: row["display_name"]?.string ?? principal,
                    direction: try ProxyGateway.text(row, "direction"), state: try ProxyGateway.text(row, "state"), preview: row["preview"]?.string, safetyNumber: Self.number(row["safety_number"]))
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }; return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> {
        let value = principal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 2048 else { return .failure(.invalidInput) }
        do { _ = try await gateway.call(.contactAdd, account: account, body: .object(["principal_id": .string(value)]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void> {
        let operation: SDKOperation = switch decision { case .accept: .contactRequestAccept; case .decline: .contactRequestDecline; case .block: .contactRequestBlock }
        do { _ = try await gateway.call(operation, account: account, body: .object(["request_id": .string(request)]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func safety(account: String, contact: ContactRecord) async -> RepositoryResult<ContactSafety> {
        guard let root = contact.rootCommitment else { return .failure(.notAvailable("The current contact identity commitment is unavailable.")) }
        do {
            let body = try await gateway.call(.contactVerificationStatus, account: account, body: .object(["contact_identity_commitment": .string(root)]))
            guard body["contact_identity_commitment"] == .string(root), let number = Self.number(body["safety_number"]) else { throw AppFailure.invalidData }
            let verified = body["verification_state"] == .string("verified")
            return .success(ContactSafety(root: root, number: number, fingerprint: try ProxyGateway.text(body, "fingerprint_hex"), verified: verified,
                requiresReview: !verified && body["stored_verification_state"] == .string("verified")))
        } catch { return .failure(AppFailure.map(error)) }
    }
    static func number(_ value: JSONValue?) -> String? {
        if let text = value?.string, text.utf8.count <= 2048 { return text }
        guard case .array(let groups) = value, !groups.isEmpty, groups.count <= 64 else { return nil }
        let parts = groups.compactMap(\.string)
        guard parts.count == groups.count, parts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 }) else { return nil }; return parts.joined(separator: " ")
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    public func unavailable(_ capability: ContactUnavailable) -> AppFailure { Self.refusal(capability) }
    static func refusal(_ capability: ContactUnavailable) -> AppFailure {
        switch capability {
        case .reporting: .notAvailable("Stranger reporting is not available in the account service yet. Decline or block remains available.")
        case .batch: .notAvailable("Batch decisions are not available yet. Review each request separately.")
        case .replyWithoutAcceptance: .notAvailable("The service does not expose this request's reply conversation yet. No contact has been accepted.")
        case .atomicSafetyVerification: .notAvailable("The verification operation is not bound to the exact fingerprint shown here. No new verification has been recorded.")
        }
    }
}
public struct UnavailableContactsRepository: ContactsRepository {
    public init() {}
    public func contacts(account: String) async -> RepositoryResult<[ContactRecord]> { .failure(.sdkUnavailable) }
    public func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]> { .failure(.sdkUnavailable) }
    public func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func safety(account: String, contact: ContactRecord) async -> RepositoryResult<ContactSafety> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
    public func unavailable(_ capability: ContactUnavailable) -> AppFailure { NativeContactsRepository.refusal(capability) }
}
