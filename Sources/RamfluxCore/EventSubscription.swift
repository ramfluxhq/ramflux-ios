// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization

private final class EventBudget: Sendable {
    private let bytes = Mutex(0)
    func claim(_ count: Int) throws {
        try bytes.withLock {
            guard count <= 4_194_304 - $0 else { throw BridgeError.resyncRequired }; $0 += count
        }
    }
    func release(_ count: Int) { bytes.withLock { $0 -= count } }
}
fileprivate final class BufferedEvent: Sendable {
    let value: JSONValue
    private let cost: Int
    private let budget: EventBudget
    fileprivate init(_ value: JSONValue, budget: EventBudget) throws {
        cost = try value.encoded().count
        try budget.claim(cost)
        self.value = value; self.budget = budget
    }
    deinit { budget.release(cost) }
}
private final class EventStopSignal: Sendable {
    private let requested = Mutex(false)
    var isRequested: Bool { requested.withLock { $0 } }
    func request() { requested.withLock { $0 = true } }
}
final class EventLifetime: Sendable {
    let queue: any EventQueue
    let stopped = DispatchGroup()
    fileprivate let requestedStop = EventStopSignal()
    init(queue: any EventQueue) { self.queue = queue; stopped.enter() }
    func cancel() { requestedStop.request(); queue.cancel() }
    func stop() async {
        cancel()
        await withCheckedContinuation { continuation in
            stopped.notify(queue: .global(qos: .utility)) { continuation.resume() }
        }
    }
    deinit { cancel() }
}
public struct EventUpdates: AsyncSequence, Sendable {
    public typealias Element = JSONValue
    fileprivate let stream: AsyncThrowingStream<BufferedEvent, any Error>
    fileprivate let lifetime: EventLifetime
    public struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var iterator: AsyncThrowingStream<BufferedEvent, any Error>.Iterator
        private let lifetime: EventLifetime
        fileprivate init(iterator: AsyncThrowingStream<BufferedEvent, any Error>.Iterator, lifetime: EventLifetime) {
            self.iterator = iterator; self.lifetime = lifetime
        }
        public mutating func next() async throws -> JSONValue? {
            defer { withExtendedLifetime(lifetime) {} }
            return try await iterator.next()?.value
        }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(iterator: stream.makeAsyncIterator(), lifetime: lifetime) }
}

/// The stream/iterator retains its native subscription independently of this handle.
/// Explicit stop is clean termination; gaps and unexpected native failures remain errors.
public final class EventSubscription: Sendable {
    public let stream: EventUpdates
    public let initialSnapshot: JSONValue
    let lifetime: EventLifetime
    init(queue: any EventQueue, capacity: Int) {
        lifetime = EventLifetime(queue: queue)
        initialSnapshot = queue.initialSnapshot
        let stopped = lifetime.stopped
        let requestedStop = lifetime.requestedStop
        let pair = AsyncThrowingStream<BufferedEvent, any Error>.makeStream(bufferingPolicy: .bufferingOldest(capacity))
        stream = EventUpdates(stream: pair.stream, lifetime: lifetime)
        let budget = EventBudget()
        pair.continuation.onTermination = { @Sendable _ in requestedStop.request(); queue.cancel() }
        DispatchQueue(label: "org.ramflux.core.events").async {
            defer { stopped.leave() }
            var failure: (any Error)?
            do {
                while !requestedStop.isRequested {
                    let events = try queue.poll()
                    for event in events {
                        if event["kind"]?.string == "lagged" { throw BridgeError.resyncRequired }
                        switch pair.continuation.yield(try BufferedEvent(event, budget: budget)) {
                        case .enqueued: break
                        case .dropped: throw BridgeError.resyncRequired
                        case .terminated: throw CancellationError()
                        @unknown default: throw BridgeError.resyncRequired
                        }
                    }
                }
            } catch {
                if !(error is CancellationError) && !(requestedStop.isRequested && ((error as? BridgeError) == .closed || (error as? CoreFailure)?.code == .closed)) { failure = error }
            }
            queue.cancel()
            do { try queue.finish() }
            catch { if failure == nil { failure = error } }
            if let failure { pair.continuation.finish(throwing: failure) }
            else { pair.continuation.finish() }
        }
    }
    public func cancel() { lifetime.cancel() }
    public func stop() async { await lifetime.stop() }
}
