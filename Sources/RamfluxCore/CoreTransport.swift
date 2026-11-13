// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization

public protocol CancellationHandle: Sendable { func cancel() }
public protocol EventQueue: Sendable {
    var initialSnapshot: JSONValue { get }
    func poll() throws -> [JSONValue]
    func cancel()
}
public protocol CoreTransport: Sendable {
    func newCancellation() throws -> any CancellationHandle
    func execute(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> JSONValue
    func executeSecret(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> JSONValue
    func subscribe(_ filter: SubscriptionFilter) throws -> any EventQueue
    func start() throws
    func suspend() throws -> JSONValue
    func resume() throws
    func close() throws
}

/// Blocking C calls run on bounded worker queues, never the main actor or Swift executor.
public final class RamfluxClient: Sendable {
    private let transport: any CoreTransport
    private let eventRegistry = EventRegistry()
    private let workers: OperationQueue
    private let lifecycleWorkers: OperationQueue
    private let admitted = Mutex((count: 0, bytes: 0))
    public init(transport: any CoreTransport) {
        self.transport = transport
        workers = OperationQueue(); workers.name = "org.ramflux.core.calls"
        workers.maxConcurrentOperationCount = 4
        lifecycleWorkers = OperationQueue(); lifecycleWorkers.name = "org.ramflux.core.lifecycle"
        lifecycleWorkers.maxConcurrentOperationCount = 1
    }
    func offload<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            workers.addOperation { continuation.resume(with: Result { try work() }) }
        }
    }
    private func admit(bytes: Int) throws {
        try admitted.withLock {
            guard $0.count < 64, bytes <= 4_194_304 - $0.bytes else { throw CoreFailure(code: 15, effect: .none) }
            $0.count += 1; $0.bytes += bytes
        }
    }
    private func release(bytes: Int) { admitted.withLock { $0.count -= 1; $0.bytes -= bytes } }
    private func lifecycle<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            lifecycleWorkers.addOperation { continuation.resume(with: Result { try work() }) }
        }
    }
    public func execute(_ request: CoreRequest) async throws -> JSONValue {
        let bytes = try request.body.encoded().count
        try admit(bytes: bytes)
        defer { release(bytes: bytes) }
        let cancellation = try transport.newCancellation()
        return try await withTaskCancellationHandler {
            if Task.isCancelled { cancellation.cancel() }
            return try await offload { [transport] in try transport.execute(request, cancellation: cancellation) }
        } onCancel: { cancellation.cancel() }
    }
    public func executeSecret(_ request: SecretRequest) async throws -> JSONValue {
        defer { request.json.erase() }
        let bytes = 16_384
        try admit(bytes: bytes)
        defer { release(bytes: bytes) }
        let cancellation = try transport.newCancellation()
        return try await withTaskCancellationHandler {
            if Task.isCancelled { cancellation.cancel() }
            return try await offload { [transport] in try transport.executeSecret(request, cancellation: cancellation) }
        } onCancel: { cancellation.cancel() }
    }
    public func start() async throws {
        try await lifecycle { [transport] in try transport.start() }
        await eventRegistry.activate()
    }
    public func suspend() async throws {
        await eventRegistry.pause()
        let report = try await lifecycle { [transport] in try transport.suspend() }
        guard report["data_root_lock_released"]?.bool == true else { throw BridgeError.lockStillHeld }
    }
    public func resume() async throws {
        try await lifecycle { [transport] in try transport.resume() }
        await eventRegistry.activate()
    }
    public func close() async throws {
        await eventRegistry.pause()
        try await lifecycle { [transport] in try transport.close() }
    }
    public func events(_ filter: SubscriptionFilter) async throws -> EventSubscription {
        try await eventRegistry.open {
            let queue = try await self.offload { [transport = self.transport] in try transport.subscribe(filter) }
            return EventSubscription(queue: queue, capacity: filter.capacity)
        }
    }
}
