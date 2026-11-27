// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public struct SettingsSnapshot: Equatable, Sendable {
    public let accountID: String?
    public let networking: AccountNetworking?
    public let devices: [DeviceRecord]
    public let nodes: [NodeRecord]
    public let retentionSeconds: Int64?
    public let requestPolicy: String?
    public init(accountID: String? = nil, networking: AccountNetworking? = nil, devices: [DeviceRecord] = [], nodes: [NodeRecord] = [], retentionSeconds: Int64? = nil, requestPolicy: String? = nil) {
        self.accountID = accountID; self.networking = networking; self.devices = devices; self.nodes = nodes; self.retentionSeconds = retentionSeconds; self.requestPolicy = requestPolicy
    }
}
public enum SettingsUnavailable: Sendable, Equatable { case openAccount, pairing, connectedServices, diagnosticExport }
public protocol SettingsRepository: Sendable {
    func pending(account: String?) async -> PendingSettingsMutation?
    func mutate(account: String?, change: SettingsMutation, operationID: String) async -> RepositoryResult<Void>
    func snapshot(account: String?) async -> RepositoryResult<SettingsSnapshot>
    func revoke(account: String, device: DeviceRecord, operationID: String) async -> RepositoryResult<Void>
    func lock(account: String) async -> RepositoryResult<Void>
    func retention(account: String, seconds: Int64, operationID: String) async -> RepositoryResult<Void>
    func setRequestPolicy(account: String, autoAccept: Bool, operationID: String) async -> RepositoryResult<Void>
    /// `account.passphrase.rotate`: the current code under `oldPassphrase`, the new one under `passphrase`
    /// (checked with its repeat by `SensitiveSubmission(values:accountCode: .new)`). Not journaled: it carries secrets.
    func changeCode(account: String, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<Void>
    func observe(account: String) async -> RepositoryObservation
    func unavailable(_ capability: SettingsUnavailable) -> AppFailure
    /// This account's username status from the username directory (`username.status`), or the status of one
    /// publication when `operationID` names it (the reply of a claim that was still pending).
    func username(account: String, operationID: String?) async -> RepositoryResult<UsernameStatus>
    /// Claims or changes this account's username (`@name` with or without the `@`). The recovery phrase in `phrase`
    /// authorizes the change and is erased on every path. Returns the status once it is committed or aborted, or
    /// still pending when the poll window ends.
    func claimUsername(account: String, name: String, phrase: SensitiveSubmission, operationID: String) async -> RepositoryResult<UsernameStatus>
    /// The app lock of the account (`account.app_lock.state`). Off by default.
    func appLock(account: String) async -> RepositoryResult<AppLockRecord>
    /// Turns the app lock on or off and sets its timeout (`account.app_lock.configure`); returns the state the SDK now reports.
    func configureAppLock(account: String, enabled: Bool, timeoutMilliseconds: UInt64, operationID: String) async -> RepositoryResult<AppLockRecord>
}
public extension SettingsRepository {
    func username(account: String, operationID: String?) async -> RepositoryResult<UsernameStatus> { .failure(.unsupported) }
    func username(account: String) async -> RepositoryResult<UsernameStatus> { await username(account: account, operationID: nil) }
    func claimUsername(account: String, name: String, phrase: SensitiveSubmission, operationID: String) async -> RepositoryResult<UsernameStatus> {
        phrase.erase(); return .failure(.unsupported)
    }
    func appLock(account: String) async -> RepositoryResult<AppLockRecord> { .failure(.unsupported) }
    func configureAppLock(account: String, enabled: Bool, timeoutMilliseconds: UInt64, operationID: String) async -> RepositoryResult<AppLockRecord> { .failure(.unsupported) }
}
public struct NativeSettingsRepository: SettingsRepository {
    private let gateway: ProxyGateway
    private let lifecycle: AccountLifecycleHooks
    private let nodes: any NodeRepository
    private let updates: NativeUpdateSource
    /// Whether the build carries a username directory pin. Without one, a directory refusal means "not set up", not "unreachable".
    private let usernameConfigured: Bool
    private let journal = RetainedMutation<SettingsMutation, Void>()
    public init(client: RamfluxClient, nodes: any NodeRepository, updates: NativeUpdateSource, lifecycle: AccountLifecycleHooks = AccountLifecycleHooks(), usernameConfigured: Bool = false) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.nodes = nodes; self.updates = updates; self.lifecycle = lifecycle; self.usernameConfigured = usernameConfigured
    }
    private func usernameFailure(_ error: any Error) -> AppFailure {
        let failure = AppFailure.mapUsername(error)
        if !usernameConfigured, case .unavailableResource("username.unavailable.directory") = failure { return .unavailableResource("username.unavailable.notConfigured") }
        return failure
    }
    public func appLock(account: String) async -> RepositoryResult<AppLockRecord> {
        do { return .success(try await AppLockService(gateway: gateway).state(account: account)) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func configureAppLock(account: String, enabled: Bool, timeoutMilliseconds: UInt64, operationID: String) async -> RepositoryResult<AppLockRecord> {
        do { return .success(try await AppLockService(gateway: gateway).configure(account: account, enabled: enabled, timeoutMilliseconds: timeoutMilliseconds, operationID: operationID)) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func snapshot(account: String?) async -> RepositoryResult<SettingsSnapshot> {
        let savedNodes: [NodeRecord]
        switch await nodes.list() { case .success(let rows): savedNodes = rows; case .failure(let failure): return .failure(failure) }
        guard let account else { return .success(SettingsSnapshot(nodes: savedNodes)) }
        do {
            let status = try await gateway.call(.accountStatus, account: account)
            let directory = try await gateway.call(.deviceList, account: account)
            let config = try await gateway.call(.accountConfigGet, account: account)
            let policy = try await gateway.call(.contactRequestsPolicyGet, account: account)
            let devices = try ProxyGateway.rows(directory, "devices").map { row in
                guard let local = row["is_local"]?.bool else { throw AppFailure.invalidData }
                let capabilities = try ProxyGateway.rows(row, "capability_scope").map { value -> String in guard let value = value.string else { throw AppFailure.invalidData }; return value }
                return DeviceRecord(id: try ProxyGateway.text(row, "device_id"), isLocal: local, capabilities: capabilities)
            }
            guard Set(devices.map(\.id)).count == devices.count else { throw AppFailure.invalidData }
            return .success(SettingsSnapshot(accountID: account, networking: status["networking"]?.string.flatMap(AccountNetworking.init(rawValue:)), devices: devices, nodes: savedNodes,
                retentionSeconds: ProxyGateway.integer(config["offline_retention_secs"]), requestPolicy: policy["contact_requests"]?.string))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func pending(account: String?) async -> PendingSettingsMutation? {
        guard let entry = await journal.snapshot(scope: account ?? "@device"), entry.unresolved else { return nil }
        return PendingSettingsMutation(change: entry.arguments, operationID: entry.operationID)
    }
    public func mutate(account: String?, change: SettingsMutation, operationID: String) async -> RepositoryResult<Void> {
        await journal.run(scope: account ?? "@device", arguments: change, operationID: operationID) {
            do {
                if case .setDefault(let node) = change { return await nodes.setDefault(node, operationID: operationID) }
                guard let account else { return .failure(.invalidInput) }
                switch change {
                case .revoke(let device):
                    guard !device.isLocal else { return .failure(.invalidInput) }
                    _ = try await gateway.call(.deviceRevoke, account: account, body: .object(["device_id": .string(device.id)]), operationID: operationID)
                case .retention(let seconds):
                    guard (3600...604800).contains(seconds) else { return .failure(.invalidInput) }
                    _ = try await gateway.call(.accountConfigSet, account: account, body: .object(["offline_retention_secs": .number(Double(seconds))]), operationID: operationID)
                case .requestPolicy(let autoAccept): _ = try await gateway.call(.contactRequestsPolicySet, account: account, body: .object(["contact_requests": .string(autoAccept ? "auto_accept" : "manual")]), operationID: operationID)
                case .lock:
                    // Account-scoped stores drop decoded plaintext before the SDK closes the account.
                    await lifecycle.notify(.willLock(account: account))
                    _ = try await gateway.call(.accountLock, account: account, operationID: operationID)
                case .signOut:
                    await lifecycle.notify(.willLeave(account: account))
                    await lifecycle.notify(.willLock(account: account))
                    _ = try await gateway.call(.accountSignOut, account: account, operationID: operationID)
                case .removeLocal:
                    // The SDK closes an open account before erasing it; the confirmation is the account id.
                    await lifecycle.notify(.willLeave(account: account))
                    await lifecycle.notify(.willLock(account: account))
                    let body = try await gateway.call(.accountRemoveLocal, account: account, body: .object(["confirmation": .string(account)]), operationID: operationID)
                    guard body["removed"]?.bool == true else { return .failure(.outcomeUnknown) }
                case .setDefault: break
                }
                return .success(())
            } catch { return .failure(AppFailure.map(error)) }
        }
    }
    public func revoke(account: String, device: DeviceRecord, operationID: String) async -> RepositoryResult<Void> { await mutate(account: account, change: .revoke(device), operationID: operationID) }
    public func retention(account: String, seconds: Int64, operationID: String) async -> RepositoryResult<Void> { await mutate(account: account, change: .retention(seconds), operationID: operationID) }
    public func setRequestPolicy(account: String, autoAccept: Bool, operationID: String) async -> RepositoryResult<Void> { await mutate(account: account, change: .requestPolicy(autoAccept: autoAccept), operationID: operationID) }
    public func changeCode(account: String, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<Void> {
        defer { credentials.erase() }
        if let issue = credentials.accountCodeIssue { return .failure(.accountCode(issue)) }
        guard let fields = credentials.take(), let current = fields["old_passphrase"], let next = fields["passphrase"] else { return .failure(.invalidInput) }
        do { _ = try await gateway.call(.accountPassphraseRotate, account: account, operationID: operationID, secrets: ["old_passphrase": current, "new_passphrase": next]); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func username(account: String, operationID: String?) async -> RepositoryResult<UsernameStatus> {
        do {
            let body = try await gateway.call(.usernameStatus, account: account, body: operationID.map { .object(["operation_id": .string($0)]) } ?? .object([:]))
            return .success(try UsernameStatus.parse(body))
        } catch { EventDiagnostics.failed("username.status", error); return .failure(usernameFailure(error)) }
    }
    /// The claim: `username.mutate` prepare (the draft operation stays admitted), authorization with the recovery phrase
    /// through the C ABI, release of the draft, then submit and a status poll (2 s steps, 30 s). The phrase is erased
    /// on every path, including a claim cancelled before it runs.
    public func claimUsername(account: String, name: String, phrase: SensitiveSubmission, operationID: String) async -> RepositoryResult<UsernameStatus> {
        defer { phrase.erase() }
        guard let query = UsernameInput.name(name) else { return .failure(.invalidInput) }
        let change: JSONValue = .object(["change": .string("set"), "name": .string(query)])
        do {
            let prepared = try await prepareClaim(account: account, change: change, operationID: operationID)
            let draft = prepared.operation
            defer { draft.release() }
            guard let drafted = prepared.response["draft"], drafted != .null else {
                return .success(try UsernameStatus.parse(prepared.response["status"] ?? .null))
            }
            guard let fields = phrase.take(), case .text(let words)? = fields["phrase"] else { return .failure(.invalidInput) }
            let publicRequest: JSONValue = .object(["account_id": .string(account), "request_id": .string(String(draft.requestID)),
                "draft": drafted, "expected_change": change])
            let signed = try await gateway.proxy.client.authorizeUsername(draft, publicRequest: publicRequest, phrase: words)
            return try await submitClaim(account: account, signed: signed, operationID: operationID)
        } catch { EventDiagnostics.failed("username.mutate", error); return .failure(usernameFailure(error)) }
    }
    private func prepareClaim(account: String, change: JSONValue, operationID: String) async throws -> (response: JSONValue, operation: UsernameDraftOperation) {
        let context = try gateway.context(.usernameMutate, account: account, operationID: operationID)
        let body: JSONValue = .object(["phase": .string("prepare"), "change": change])
        let request = try CoreRequest(method: SDKOperation.usernameMutate.rawValue, sdkAPI: SDKOperation.usernameMutate.capability, accountID: account,
            operationID: context.operationID, body: body, deadlineUnixMilliseconds: context.deadlineUnixMilliseconds)
        return try await gateway.proxy.client.prepareUsername(request)
    }
    private func submitClaim(account: String, signed: JSONValue, operationID: String) async throws -> RepositoryResult<UsernameStatus> {
        let operationNode: JSONValue? = signed["operation"]
        let bodyNode: JSONValue? = operationNode?["body"]
        let signedOperation: String? = bodyNode?["operation_id"]?.string
        let submitBody: JSONValue = .object(["phase": .string("submit"), "signed": signed])
        let submitted: JSONValue
        do { submitted = try await gateway.call(.usernameMutate, account: account, body: submitBody, operationID: operationID) }
        catch {
            // A lost submit reply is reconciled with the publication's status before the failure is shown.
            if let signedOperation, case .success(let status) = await username(account: account, operationID: signedOperation), status.state != .empty {
                return .success(status)
            }
            throw error
        }
        var status = try UsernameStatus.parse(submitted)
        guard let operation = signedOperation ?? status.operationID else { return .success(status) }
        let deadline = Date().addingTimeInterval(30)
        while status.state == .pending, Date() < deadline {
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return .success(status) }
            let body = try await gateway.call(.usernameStatus, account: account, body: .object(["operation_id": .string(operation)]))
            status = try UsernameStatus.parse(body)
        }
        return .success(UsernameStatus(state: status.state, name: status.name, operationID: operation))
    }
    public func lock(account: String) async -> RepositoryResult<Void> { await mutate(account: account, change: .lock, operationID: await pending(account: account)?.operationID ?? UUID().uuidString) }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    public func unavailable(_ capability: SettingsUnavailable) -> AppFailure { Self.refusal(capability) }
    static func refusal(_ capability: SettingsUnavailable) -> AppFailure {
        switch capability {
        case .openAccount: .unavailableResource("settings.unavailable.openAccount")
        case .pairing: .unavailableResource("settings.unavailable.pairing")
        case .connectedServices: .unavailableResource("settings.unavailable.connectedServices")
        case .diagnosticExport: .unavailableResource("settings.unavailable.diagnosticExport")
        }
    }
}
public struct UnavailableSettingsRepository: SettingsRepository {
    public init() {}
    public func snapshot(account: String?) async -> RepositoryResult<SettingsSnapshot> { .failure(.sdkUnavailable) }
    public func revoke(account: String, device: DeviceRecord, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func lock(account: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func retention(account: String, seconds: Int64, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func setRequestPolicy(account: String, autoAccept: Bool, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func changeCode(account: String, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<Void> { credentials.erase(); return .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
    public func unavailable(_ capability: SettingsUnavailable) -> AppFailure { NativeSettingsRepository.refusal(capability) }
}

public extension SettingsRepository {
    func pending(account: String?) async -> PendingSettingsMutation? { nil }
    func mutate(account: String?, change: SettingsMutation, operationID: String) async -> RepositoryResult<Void> {
        guard let account else { return .failure(.invalidInput) }
        switch change { case .revoke(let device): return await revoke(account: account, device: device, operationID: operationID)
        case .retention(let seconds): return await retention(account: account, seconds: seconds, operationID: operationID)
        case .requestPolicy(let autoAccept): return await setRequestPolicy(account: account, autoAccept: autoAccept, operationID: operationID)
        case .lock: return await lock(account: account)
        case .setDefault, .signOut, .removeLocal: return .failure(.unsupported) }
    }
}
