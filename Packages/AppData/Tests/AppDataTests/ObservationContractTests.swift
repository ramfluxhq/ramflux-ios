// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import RamfluxCore
@testable import AppData
private final class EventTrace: Sendable {
    let values = Mutex<[String]>([])
    func append(_ value: String) { values.withLock { $0.append(value) } }
    func snapshot() -> [String] { values.withLock { $0 } }
}
private final class RecordingQueue: EventQueue {
    let initialSnapshot: JSONValue = .object([:])
    let wake = DispatchSemaphore(value: 0), finishRelease = DispatchSemaphore(value: 0)
    let finishStarted = AsyncStream<Void>.makeStream()
    let trace: EventTrace
    let account: String
    let blockFinish: Bool
    init(account: String, trace: EventTrace, blockFinish: Bool) { self.account = account; self.trace = trace; self.blockFinish = blockFinish }
    func poll() throws -> [JSONValue] { _ = wake.wait(timeout: .now() + 5); throw BridgeError.closed }
    func cancel() { wake.signal() }
    func finish() throws {
        trace.append("finish-start:" + account); finishStarted.continuation.yield(())
        if blockFinish { guard finishRelease.wait(timeout: .now() + 5) == .success else { throw AppFailure.failed } }
        trace.append("finish-end:" + account); finishStarted.continuation.finish()
    }
}
/// A queue the test feeds: each `push` releases one poll with the given frames.
private final class ScriptedQueue: EventQueue {
    let initialSnapshot: JSONValue = .object([:])
    private let pending = Mutex<[[JSONValue]]>([])
    private let closed = Mutex(false)
    private let signal = DispatchSemaphore(value: 0)
    let finished = Mutex(false)
    func push(_ frames: [JSONValue]) { pending.withLock { $0.append(frames) }; signal.signal() }
    func poll() throws -> [JSONValue] {
        while true {
            if closed.withLock({ $0 }) { throw BridgeError.closed }
            if let next = pending.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { return next }
            _ = signal.wait(timeout: .now() + 0.05)
        }
    }
    func cancel() { closed.withLock { $0 = true }; signal.signal() }
    func finish() throws { finished.withLock { $0 = true } }
}
private final class QueueFactory: Sendable {
    let queues = Mutex<[ScriptedQueue]>([])
    func make() -> ScriptedQueue { let queue = ScriptedQueue(); queues.withLock { $0.append(queue) }; return queue }
    var count: Int { queues.withLock { $0.count } }
    var last: ScriptedQueue? { queues.withLock { $0.last } }
}
private let changed: JSONValue = .object(["kind": .string("event"), "topic": .string("conversation.changed")])
private func waitFor(_ condition: @Sendable () -> Bool) async {
    for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}
@Suite(.timeLimit(.minutes(1))) struct ObservationContractTests {
    @Test func observersShareOneNativeSubscriptionAndTheLastStopEndsIt() async {
        let factory = QueueFactory()
        let transport = ProxyTransport(onSubscribe: { _ in factory.make() }) { _ in .object([:]) }
        let source = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let first = await source.observe(account: "A"), second = await source.observe(account: "A")
        var a = first.stream.makeAsyncIterator(), b = second.stream.makeAsyncIterator()
        #expect(await a.next() == .invalidated); #expect(await b.next() == .invalidated)
        #expect(factory.count == 1); #expect(await source.observerCount == 2)
        factory.last?.push([changed])
        #expect(await a.next() == .invalidated); #expect(await b.next() == .invalidated)
        await first.stop()
        #expect(await source.observerCount == 1); #expect(factory.last?.finished.withLock { $0 } == false)
        factory.last?.push([changed]); #expect(await b.next() == .invalidated)
        await second.stop()
        #expect(await source.observerCount == 0); #expect(factory.last?.finished.withLock { $0 } == true)
        #expect(factory.count == 1)
    }
    @Test func transientFramesReachOnlyObserversThatAskAndNeverInvalidate() async {
        let factory = QueueFactory()
        let transport = ProxyTransport(onSubscribe: { _ in factory.make() }) { _ in .object([:]) }
        let source = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let chat = await source.observe(account: "A", transientFrames: true), list = await source.observe(account: "A")
        #expect(list.transient == nil)
        var updates = chat.stream.makeAsyncIterator(), other = list.stream.makeAsyncIterator()
        guard var frames = chat.transient?.makeAsyncIterator() else { Issue.record("no transient stream"); return }
        _ = await updates.next(); _ = await other.next()
        let typing: JSONValue = .object(["kind": .string("event"), "topic": .string("message.transient"), "body": .object(["typing": .bool(true)])])
        factory.last?.push([typing])
        let frame = await frames.next()
        #expect(frame?.topic == "message.transient")
        #expect(frame.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0.body) } == .object(["typing": .bool(true)]))
        factory.last?.push([changed])
        // The next update after the transient frame is the durable change, not an invalidation for the frame.
        #expect(await updates.next() == .invalidated); #expect(await other.next() == .invalidated)
        await chat.stop(); await list.stop()
        #expect(await frames.next() == nil)
    }
    @Test func lagResubscribesAutomaticallyAndKeepsEveryObserverLive() async {
        let factory = QueueFactory(), resets = Mutex(0)
        let transport = ProxyTransport(onReset: { resets.withLock { $0 += 1 } }, onSubscribe: { _ in factory.make() }) { _ in .object([:]) }
        let source = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let first = await source.observe(account: "A"), second = await source.observe(account: "A")
        var a = first.stream.makeAsyncIterator(), b = second.stream.makeAsyncIterator()
        _ = await a.next(); _ = await b.next()
        factory.last?.push([.object(["kind": .string("lagged")])])
        await waitFor { factory.count == 2 }
        #expect(factory.count == 2); #expect(resets.withLock { $0 } == 2)
        #expect(await a.next() == .invalidated); #expect(await b.next() == .invalidated)
        factory.last?.push([changed])
        #expect(await a.next() == .invalidated); #expect(await b.next() == .invalidated)
        #expect(await source.observerCount == 2)
        await first.stop(); await second.stop()
    }
    @Test func repeatedResyncWithoutDeliveryFailsEveryObserver() async {
        let factory = QueueFactory()
        let transport = ProxyTransport(onSubscribe: { _ in let queue = factory.make(); queue.push([.object(["kind": .string("lagged")])]); return queue }) { _ in .object([:]) }
        let source = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let observation = await source.observe(account: "A")
        var last: RepositoryUpdate?
        for await update in observation.stream { last = update }
        #expect(last == .failed(AppFailure.map(BridgeError.resyncRequired)))
        #expect(factory.count == NativeUpdateSource.resyncLimit + 1)
        #expect(await source.observerCount == 0)
        await observation.stop()
    }
    @Test func cancelledConsumerIsRemovedWithoutStop() async {
        let factory = QueueFactory()
        let transport = ProxyTransport(onSubscribe: { _ in factory.make() }) { _ in .object([:]) }
        let source = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let consumer = Task { let observation = await source.observe(account: "A"); for await _ in observation.stream {} }
        await waitFor { factory.count == 1 }
        consumer.cancel(); await consumer.value
        for _ in 0..<400 { if await source.observerCount == 0 { break }; try? await Task.sleep(for: .milliseconds(5)) }
        #expect(await source.observerCount == 0)
        await waitFor { factory.last?.finished.withLock { $0 } == true }
        #expect(factory.last?.finished.withLock { $0 } == true)
    }
    @Test func accountReplacementJoinsOldNativeStopBeforeResetAndSubscribe() async {
        let trace = EventTrace()
        let first = RecordingQueue(account: "A", trace: trace, blockFinish: true), second = RecordingQueue(account: "B", trace: trace, blockFinish: false)
        defer { first.finishRelease.signal(); first.cancel(); second.cancel() }
        let transport = ProxyTransport(onReset: { trace.append("reset") }, onSubscribe: { filter in
            trace.append("subscribe:" + (filter.accountID ?? "nil"))
            return filter.accountID == "A" ? first : second
        }) { _ in .object([:]) }
        let source = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let old = await source.observe(account: "A"); var initial = old.stream.makeAsyncIterator()
        #expect(await initial.next() == .invalidated)
        let replacement = Task { await source.observe(account: "B") }
        var finishing = first.finishStarted.stream.makeAsyncIterator(); _ = await finishing.next()
        #expect(trace.snapshot() == ["reset", "subscribe:A", "finish-start:A"])
        first.finishRelease.signal(); let new = await replacement.value
        var next = new.stream.makeAsyncIterator(); #expect(await next.next() == .invalidated)
        #expect(Array(trace.snapshot().prefix(6)) == ["reset", "subscribe:A", "finish-start:A", "finish-end:A", "reset", "subscribe:B"])
        await new.stop()
    }
}
