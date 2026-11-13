// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import CRamflux
import Synchronization

final class NativeCancellation: CancellationHandle {
    private struct State { var cancelled = false; var handles: (UInt64, UInt64)? }
    private let state = Mutex(State())
    var isCancelled: Bool { state.withLock { $0.cancelled } }
    func attach(client: UInt64, operation: UInt64) {
        state.withLock {
            $0.handles = (client, operation)
            if $0.cancelled { _ = ramflux_v2_operation_cancel(client, operation) }
        }
    }
    func detach() { state.withLock { $0.handles = nil } }
    func cancel() {
        state.withLock {
            $0.cancelled = true
            if let (client, operation) = $0.handles { _ = ramflux_v2_operation_cancel(client, operation) }
        }
    }
}
