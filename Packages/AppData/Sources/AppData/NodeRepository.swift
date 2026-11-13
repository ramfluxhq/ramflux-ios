// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public protocol NodeRepository: Sendable {
    func list() async -> RepositoryResult<[NodeRecord]>
    func inspect(_ origin: String) async -> RepositoryResult<NodeRecord>
    func save(_ node: NodeRecord, expectedPublicKey: String, operationID: String) async -> RepositoryResult<Void>
    func setDefault(_ node: NodeRecord, operationID: String) async -> RepositoryResult<Void>
}
public struct NativeNodeRepository: NodeRepository {
    private let gateway: ProxyGateway
    public init(client: RamfluxClient) { gateway = ProxyGateway(proxy: SDKProxy(client: client)) }
    public func list() async -> RepositoryResult<[NodeRecord]> {
        do {
            let body = try await gateway.call(.nodeList)
            let records = try ProxyGateway.rows(body, "nodes").map { row in
                let id = try ProxyGateway.text(row, "node_id")
                return NodeRecord(id: id, origin: try ProxyGateway.text(row, "discovery_url"), publicKey: row["node_public_key"]?.string,
                                  isDefault: body["default_node_id"] == .string(id), enabled: row["enabled"]?.bool ?? false, isConfirmed: true, pinSource: row["pin_source"]?.string)
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }
            return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func inspect(_ origin: String) async -> RepositoryResult<NodeRecord> {
        do {
            let body = try await gateway.call(.nodeAdd, body: .object(["url": .string(origin)]))
            guard let row = body["node"] else { throw AppFailure.invalidData }
            return .success(NodeRecord(id: try ProxyGateway.text(row, "node_id"), origin: try ProxyGateway.text(row, "discovery_url"),
                                       fingerprint: try ProxyGateway.text(body, "key_fingerprint"), publicKey: try ProxyGateway.text(row, "node_public_key")))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func save(_ node: NodeRecord, expectedPublicKey: String, operationID: String) async -> RepositoryResult<Void> {
        guard let key = node.publicKey, node.fingerprint != nil else { return .failure(.invalidData) }
        guard !expectedPublicKey.isEmpty, expectedPublicKey == key else { return .failure(.nodeKeyMismatch) }
        do { _ = try await gateway.call(.nodeConfirm, body: .object(["node_id": .string(node.id), "expected_public_key": .string(expectedPublicKey), "pin_source": .string("operator")]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func setDefault(_ node: NodeRecord, operationID: String) async -> RepositoryResult<Void> {
        do { _ = try await gateway.call(.nodeSetDefault, body: .object(["node_id": .string(node.id)]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
}
public struct UnavailableNodeRepository: NodeRepository {
    public init() {}
    public func list() async -> RepositoryResult<[NodeRecord]> { .failure(.sdkUnavailable) }
    public func inspect(_ origin: String) async -> RepositoryResult<NodeRecord> { .failure(.sdkUnavailable) }
    public func save(_ node: NodeRecord, expectedPublicKey: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func setDefault(_ node: NodeRecord, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
}
