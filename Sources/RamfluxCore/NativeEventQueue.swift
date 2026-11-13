// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import CRamflux
import Darwin

final class NativeEventQueue: EventQueue {
    let initialSnapshot: JSONValue
    private let cancelled = Mutex(false)
    private let core: NativeCore
    private let operation: NativeOperation
    private let identity: EventIdentity
    init(core: NativeCore, operation: NativeOperation, snapshot: JSONValue, identity: EventIdentity) {
        self.core = core; self.operation = operation; initialSnapshot = snapshot; self.identity = identity
    }
    func poll() throws -> [JSONValue] {
        if cancelled.withLock({ $0 }) { throw CancellationError() }
        var events: UnsafeMutablePointer<RamfluxBuffer>?
        let code = ramflux_v2_event_poll(operation.client, &events)
        if code == 0 || code == 27 {
            let frame = try JSONValue.decode(NativeBuffers.take(events))
            guard identity.accepts(frame) else { return [] }
            if code == 27 { throw BridgeError.resyncRequired }
            return [frame]
        }
        if let events { rf_buffer_wipe_free(events) }
        if code == 24 { usleep(10_000); return [] }
        if code == 27 { throw BridgeError.resyncRequired }
        throw CoreFailure(code: code, effect: .unknown)
    }
    func cancel() {
        cancelled.withLock { cancelled in
            guard !cancelled else { return }
            cancelled = true
            operation.finish()
        }
    }
    func finish() throws {
        cancel()
        for attempt in 0..<3 {
            let code = operation.finish()
            if code == 0 { try core.finishSubscription(client: operation.client); return }
            guard code == 15, attempt < 2 else { throw CoreFailure(code: code, effect: .none) }
            usleep(20_000)
        }
    }
    deinit { cancel() }
}
