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
    func snapshot(account: String?) async -> RepositoryResult<SettingsSnapshot>
    func revoke(account: String, device: DeviceRecord, operationID: String) async -> RepositoryResult<Void>
    func lock(account: String) async -> RepositoryResult<Void>
    func retention(account: String, seconds: Int64, operationID: String) async -> RepositoryResult<Void>
    func requireManualRequests(account: String, operationID: String) async -> RepositoryResult<Void>
    func observe(account: String) async -> RepositoryObservation
    func unavailable(_ capability: SettingsUnavailable) -> AppFailure
}
public struct NativeSettingsRepository: SettingsRepository {
    private let gateway: ProxyGateway
    private let nodes: any NodeRepository
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, nodes: any NodeRepository, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.nodes = nodes; self.updates = updates }
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
    public func revoke(account: String, device: DeviceRecord, operationID: String) async -> RepositoryResult<Void> {
        guard !device.isLocal else { return .failure(.invalidInput) }
        do { _ = try await gateway.call(.deviceRevoke, account: account, body: .object(["device_id": .string(device.id)]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func lock(account: String) async -> RepositoryResult<Void> {
        do { _ = try await gateway.call(.accountLock, account: account); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func retention(account: String, seconds: Int64, operationID: String) async -> RepositoryResult<Void> {
        guard (3600...604800).contains(seconds) else { return .failure(.invalidInput) }
        do { _ = try await gateway.call(.accountConfigSet, account: account, body: .object(["offline_retention_secs": .number(Double(seconds))]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func requireManualRequests(account: String, operationID: String) async -> RepositoryResult<Void> {
        do { _ = try await gateway.call(.contactRequestsPolicySet, account: account, body: .object(["contact_requests": .string("manual")]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    public func unavailable(_ capability: SettingsUnavailable) -> AppFailure { Self.refusal(capability) }
    static func refusal(_ capability: SettingsUnavailable) -> AppFailure {
        switch capability {
        case .openAccount: .notAvailable("Open-account and username reachability are not available in the account service yet. They are separate from automatically accepting requests.")
        case .pairing: .notAvailable("The phone pairing coordinator is not registered. No device code or authorization has been created.")
        case .connectedServices: .notAvailable("Advanced connected-service configuration is managed on your desktop.")
        case .diagnosticExport: .notAvailable("Sanitized diagnostic export is not available in this build. No private account data has been shared.")
        }
    }
}
public struct UnavailableSettingsRepository: SettingsRepository {
    public init() {}
    public func snapshot(account: String?) async -> RepositoryResult<SettingsSnapshot> { .failure(.sdkUnavailable) }
    public func revoke(account: String, device: DeviceRecord, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func lock(account: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func retention(account: String, seconds: Int64, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func requireManualRequests(account: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
    public func unavailable(_ capability: SettingsUnavailable) -> AppFailure { NativeSettingsRepository.refusal(capability) }
}
