// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

public struct RequestContext: Sendable {
    public let accountID: String?
    public let operationID: OperationID?
    public let deadlineUnixMilliseconds: UInt64
    public init(accountID: String? = nil, operationID: OperationID? = nil, deadlineUnixMilliseconds: UInt64) {
        self.accountID = accountID; self.operationID = operationID
        self.deadlineUnixMilliseconds = deadlineUnixMilliseconds
    }
}

public protocol SDKProxyProtocol: Sendable { var client: RamfluxClient { get } }
public extension SDKProxyProtocol {
    func perform(_ operation: SDKOperation, context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {
        guard !operation.requiresSecureInput else { throw BridgeError.invalidInput }
        return try await client.execute(makeRequest(operation, context: context, body: body))
    }
    func performSecret(_ operation: SDKOperation, context: RequestContext, body: JSONValue = .object([:]),
                       secrets: [String: SecretField]) async throws -> JSONValue {
        defer { secrets.values.forEach { $0.erase() } }
        let request = try makeRequest(operation, context: context, body: body)
        return try await client.executeSecret(SecretRequest(request: request, fields: secrets))
    }
    private func makeRequest(_ operation: SDKOperation, context: RequestContext, body: JSONValue) throws -> CoreRequest {
        guard !operation.requiresOperationID || context.operationID != nil else { throw BridgeError.invalidInput }
        return try CoreRequest(method: operation.rawValue, sdkAPI: String(operation.rawValue.split(separator: ".").first ?? ""),
            accountID: context.accountID, operationID: context.operationID, body: body,
            deadlineUnixMilliseconds: context.deadlineUnixMilliseconds)
    }
}

public struct SDKProxy: AccountProxy, NodeProxy, ConversationProxy, MessageProxy, ContactProxy,
    GroupProxy, CallProxy, BotProxy, DeviceProxy, ObjectProxy, SurfaceProxy, GrantProxy, TaskProxy,
    MCPProxy, A2IProxy, A2UIProxy, SyncProxy, StreamProxy, IdentityProxy, BusProxy, DaemonProxy {
    public let client: RamfluxClient
    public init(client: RamfluxClient) { self.client = client }
}
