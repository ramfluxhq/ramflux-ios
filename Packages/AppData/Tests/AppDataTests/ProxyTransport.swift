// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import RamfluxCore
private struct ProxyCancellation: CancellationHandle { func cancel() {} }
final class ProxyTransport: CoreTransport {
    let calls = Mutex<[CoreRequest]>([])
    let onReset: @Sendable () throws -> Void
    let onSubscribe: (@Sendable (SubscriptionFilter) throws -> any EventQueue)?
    private let handler: @Sendable (CoreRequest) throws -> JSONValue
    init(onReset: @escaping @Sendable () throws -> Void = {}, onSubscribe: (@Sendable (SubscriptionFilter) throws -> any EventQueue)? = nil, _ handler: @escaping @Sendable (CoreRequest) throws -> JSONValue) { self.handler = handler; self.onReset = onReset; self.onSubscribe = onSubscribe }
    func newCancellation() throws -> any CancellationHandle { ProxyCancellation() }
    func execute(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> JSONValue { calls.withLock { $0.append(request) }; return .object(["ok": .bool(true), "body": try handler(request)]) }
    func executeSecret(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> JSONValue { try execute(request.request, cancellation: cancellation) }
    func executeSecretResponse(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> SecretBytes {
        let frame = try execute(request, cancellation: cancellation)
        let bytes = try JSONEncoder().encode(JSONValue.object(["code": .number(0), "response": frame]))
        return try bytes.withUnsafeBytes { try SecretBytes(copying: $0) }
    }
    func executeSecretRequestResponse(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> SecretBytes { try executeSecretResponse(request.request, cancellation: cancellation) }
    func start() throws {}; func close() throws {}; func resume() throws {}; func resetEvents() throws { try onReset() }
    func suspend() throws -> JSONValue { .object(["data_root_lock_released": .bool(true)]) }
    func subscribe(_ filter: SubscriptionFilter) throws -> any EventQueue { guard let onSubscribe else { throw BridgeError.invalidInput }; return try onSubscribe(filter) }
}
