// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public struct CeremonyMetadata: Equatable, Sendable {
    public let id: String
    public let expiresInMilliseconds: Int64
    public let anchor: String?
    public init(id: String, expiresInMilliseconds: Int64, anchor: String? = nil) { self.id = id; self.expiresInMilliseconds = expiresInMilliseconds; self.anchor = anchor }
}
public protocol OnboardingRepository: Sendable {
    func begin(name: String, nodeID: String?) async -> RepositoryResult<CeremonyMetadata>
    func showPhrase() async -> RepositoryResult<RecoveryDisplay>
    func hideAndChallenge() async -> RepositoryResult<[Int]>
    func confirm(_ submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord>
    func beginRecovery(accountID: String) async -> RepositoryResult<CeremonyMetadata>
    func confirmRecovery(anchor: String, submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord>
    func unlock(accountID: String, submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord>
    func cancel() async -> RepositoryResult<Void>
}
public actor NativeOnboardingRepository: OnboardingRepository {
    private let proxy: SDKProxy
    private let gateway: ProxyGateway
    private var ceremony: AccountCeremony?
    private var recovery = false
    private var display: RecoveryDisplay?
    public init(client: RamfluxClient) { proxy = SDKProxy(client: client); gateway = ProxyGateway(proxy: SDKProxy(client: client)) }
    public func begin(name: String, nodeID: String?) async -> RepositoryResult<CeremonyMetadata> {
        guard ceremony == nil else { return .failure(.busy) }
        let ceremony = AccountCeremony(proxy: proxy, kind: .creation); self.ceremony = ceremony; recovery = false
        do {
            var body: [String: JSONValue] = ["display_name": .string(name), "principal_kind": .string("human")]
            if let nodeID { body["node_id"] = .string(nodeID) }
            let result = try await ceremony.begin(context: gateway.context(.accountCreateBegin), body: .object(body))
            return .success(try Self.metadata(ProxyGateway.body(result)))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func showPhrase() async -> RepositoryResult<RecoveryDisplay> {
        guard let ceremony, !recovery else { return .failure(.invalidInput) }
        do {
            let value = try RecoveryDisplay(await ceremony.showPhraseOnce(context: gateway.context(.accountCreateShowOnce)))
            display = value; return .success(value)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func hideAndChallenge() async -> RepositoryResult<[Int]> {
        guard let ceremony, !recovery else { return .failure(.invalidInput) }
        display?.erase(); display = nil
        do {
            try await ceremony.hidePhrase()
            let body = try ProxyGateway.body(await ceremony.challenge(context: gateway.context(.accountCreateHiddenChallenge)))
            let positions = try ProxyGateway.rows(body, "positions").map { value -> Int in
                guard let number = ProxyGateway.integer(value), (1...24).contains(number) else { throw AppFailure.invalidData }; return Int(number)
            }
            guard positions.count == 3, Set(positions).count == 3 else { throw AppFailure.invalidData }
            return .success(positions)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func confirm(_ submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord> {
        defer { submission.erase() }
        guard let ceremony, !recovery, let fields = submission.take(), fields["words"] != nil, fields["passphrase"] != nil else { return .failure(.invalidInput) }
        do {
            let result = try await ceremony.confirm(context: gateway.context(.accountCreateConfirm), fields: fields)
            guard case .sealed(let frame) = result else { throw AppFailure.invalidData }
            let record = try Self.account(ProxyGateway.body(frame)); self.ceremony = nil; return .success(record)
        } catch { return .failure(.outcomeUnknown) }
    }
    public func beginRecovery(accountID: String) async -> RepositoryResult<CeremonyMetadata> {
        guard ceremony == nil else { return .failure(.busy) }
        let ceremony = AccountCeremony(proxy: proxy, kind: .recovery); self.ceremony = ceremony; recovery = true
        do { return .success(try Self.metadata(ProxyGateway.body(await ceremony.begin(context: gateway.context(.accountRecoverBegin), body: .object(["account_id": .string(accountID)]))))) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func confirmRecovery(anchor: String, submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord> {
        defer { submission.erase() }
        guard let ceremony, recovery, let fields = submission.take(), fields["phrase"] != nil, fields["passphrase"] != nil else { return .failure(.invalidInput) }
        do {
            let result = try await ceremony.confirm(context: gateway.context(.accountRecoverConfirm), body: .object(["confirmed_anchor": .string(anchor)]), fields: fields)
            guard case .sealed(let frame) = result else { throw AppFailure.invalidData }
            let record = try Self.account(ProxyGateway.body(frame)); self.ceremony = nil; return .success(record)
        } catch { return .failure(.outcomeUnknown) }
    }
    public func unlock(accountID: String, submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord> {
        defer { submission.erase() }
        guard let fields = submission.take(), fields["passphrase"] != nil else { return .failure(.invalidInput) }
        do { return .success(try Self.account(await gateway.call(.accountUnlock, account: accountID, secrets: fields))) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func cancel() async -> RepositoryResult<Void> {
        display?.erase(); display = nil
        guard let ceremony else { return .success(()) }
        do { try await ceremony.cancel(context: gateway.context(recovery ? .accountRecoverCancel : .accountCreateCancel)); self.ceremony = nil; return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    private static func metadata(_ body: JSONValue) throws -> CeremonyMetadata {
        guard let expiry = ProxyGateway.integer(body["expires_in_ms"]), expiry > 0 else { throw AppFailure.invalidData }
        return CeremonyMetadata(id: try ProxyGateway.text(body, "ceremony_id"), expiresInMilliseconds: expiry, anchor: body["account_anchor"]?.string)
    }
    private static func account(_ body: JSONValue) throws -> AccountRecord {
        AccountRecord(id: try ProxyGateway.text(body, "account_id"), displayName: try ProxyGateway.text(body, "display_name"), isLocked: false)
    }
    deinit { display?.erase() }
}
public struct UnavailableOnboardingRepository: OnboardingRepository {
    public init() {}
    public func begin(name: String, nodeID: String?) async -> RepositoryResult<CeremonyMetadata> { .failure(.sdkUnavailable) }
    public func showPhrase() async -> RepositoryResult<RecoveryDisplay> { .failure(.sdkUnavailable) }
    public func hideAndChallenge() async -> RepositoryResult<[Int]> { .failure(.sdkUnavailable) }
    public func confirm(_ submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord> { submission.erase(); return .failure(.sdkUnavailable) }
    public func beginRecovery(accountID: String) async -> RepositoryResult<CeremonyMetadata> { .failure(.sdkUnavailable) }
    public func confirmRecovery(anchor: String, submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord> { submission.erase(); return .failure(.sdkUnavailable) }
    public func unlock(accountID: String, submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord> { submission.erase(); return .failure(.sdkUnavailable) }
    public func cancel() async -> RepositoryResult<Void> { .success(()) }
}
