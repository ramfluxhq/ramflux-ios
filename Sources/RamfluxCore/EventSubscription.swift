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
public struct EventUpdates: AsyncSequence, Sendable {
    public typealias Element = JSONValue
    fileprivate let stream: AsyncThrowingStream<BufferedEvent, any Error>
    public struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var iterator: AsyncThrowingStream<BufferedEvent, any Error>.Iterator
        public mutating func next() async throws -> JSONValue? { try await iterator.next()?.value }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(iterator: stream.makeAsyncIterator()) }
}

/// One app-session consumer. Cancel before closing the client on background; then reopen
/// and subscribe from the consumer's last APPLIED journal cursor on foreground.
public final class EventSubscription: Sendable {
    public let stream: EventUpdates
    public let initialSnapshot: JSONValue
    private let stopped = DispatchGroup()
    private let queue: any EventQueue
    init(queue: any EventQueue, capacity: Int) {
        self.queue = queue
        initialSnapshot = queue.initialSnapshot
        stopped.enter()
        let stopped = self.stopped
        let pair = AsyncThrowingStream<BufferedEvent, any Error>.makeStream(bufferingPolicy: .bufferingOldest(capacity))
        stream = EventUpdates(stream: pair.stream)
        let budget = EventBudget()
        pair.continuation.onTermination = { @Sendable _ in queue.cancel() }
        DispatchQueue(label: "org.ramflux.core.events").async {
            defer { stopped.leave() }
            do {
                while true {
                    let events = try queue.poll()
                    for event in events {
                        if event["kind"]?.string == "lagged" { throw BridgeError.resyncRequired }
                        switch pair.continuation.yield(try BufferedEvent(event, budget: budget)) {
                        case .enqueued: break
                        case .dropped: throw BridgeError.resyncRequired
                        case .terminated: queue.cancel(); return
                        @unknown default: throw BridgeError.resyncRequired
                        }
                    }
                }
            } catch { queue.cancel(); pair.continuation.finish(throwing: error) }
        }
    }
    public func cancel() { queue.cancel() }
    public func stop() async {
        queue.cancel()
        await withCheckedContinuation { continuation in
            stopped.notify(queue: .global(qos: .utility)) { continuation.resume() }
        }
    }
    deinit { queue.cancel() }
}
