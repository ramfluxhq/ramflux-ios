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
@Suite(.timeLimit(.minutes(1))) struct ObservationContractTests {
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
