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
    private let client: UInt64
    init(core: NativeCore, clientHandle: UInt64, snapshot: JSONValue) { self.core = core; client = clientHandle; initialSnapshot = snapshot }
    func poll() throws -> [JSONValue] {
        guard !cancelled.withLock({ $0 }) else { throw BridgeError.closed }
        var events: UnsafeMutablePointer<RamfluxBuffer>?
        let code = ramflux_v2_event_poll(client, &events)
        if code == 0 { return [try JSONValue.decode(NativeBuffers.take(events))] }
        if let events { rf_buffer_wipe_free(events) }
        if code == 24 { usleep(10_000); return [] }
        if code == 27 { throw BridgeError.resyncRequired }
        throw CoreFailure(code: code, effect: .unknown)
    }
    func cancel() { cancelled.withLock { $0 = true } }
    deinit { cancel() }
}
