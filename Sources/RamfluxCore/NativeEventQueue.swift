// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import CRamflux
import Darwin
#if DEBUG
import os
private let eventTrace = Logger(subsystem: "org.ramflux.ios", category: "events")
#endif

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
            #if DEBUG
            // Method and match flags only, never the body (see EventDiagnostics in AppData).
            let method = frame["method"]?.string ?? "?"
            eventTrace.notice("native event method=\(method, privacy: .public) status=\(code) generation_match=\(frame["subscription_generation"] == .string(String(self.identity.generation))) account_present=\(frame["account_id"]?.string != nil) accepted=\(self.identity.accepts(frame))")
            #endif
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
