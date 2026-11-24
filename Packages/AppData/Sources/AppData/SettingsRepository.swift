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
public enum SettingsUnavailable: Sendable, Equatable { case openAccount, pairing, connectedServices, diagnosticExport
    /// Claiming a username needs the recovery-phrase ceremony (`ramflux_v2_username_authorize`), which this
    /// build does not offer yet; the screen shows the directory's own status or refusal.
    case username
}
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
    /// This account's username from the username directory (`username.status`); nil when none is claimed.
    func username(account: String) async -> RepositoryResult<String?>
}
public extension SettingsRepository {
    func username(account: String) async -> RepositoryResult<String?> { .failure(unavailable(.username)) }
}
public struct NativeSettingsRepository: SettingsRepository {
    private let gateway: ProxyGateway
    private let lifecycle: AccountLifecycleHooks
    private let nodes: any NodeRepository
    private let updates: NativeUpdateSource
    private let journal = RetainedMutation<SettingsMutation, Void>()
    public init(client: RamfluxClient, nodes: any NodeRepository, updates: NativeUpdateSource, lifecycle: AccountLifecycleHooks = AccountLifecycleHooks()) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.nodes = nodes; self.updates = updates; self.lifecycle = lifecycle }
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
                    await lifecycle.notify(.willLock(account: account))
                    _ = try await gateway.call(.accountSignOut, account: account, operationID: operationID)
                case .removeLocal:
                    // The SDK closes an open account before erasing it; the confirmation is the account id.
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
    public func username(account: String) async -> RepositoryResult<String?> {
        do {
            let body = try await gateway.call(.usernameStatus, account: account, body: .object([:]))
            let name = (body["username"] ?? body["name"])?.string.flatMap { $0.isEmpty || $0.utf8.count > 256 ? nil : $0 }
            return .success(name)
        } catch { EventDiagnostics.failed("username.status", error); return .failure(AppFailure.mapUsername(error)) }
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
        case .username: .unavailableResource("username.unavailable.claim")
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
