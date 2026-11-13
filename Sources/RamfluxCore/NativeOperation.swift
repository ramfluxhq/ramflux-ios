// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Synchronization
import CRamflux

/// Retained by a subscription after its opening reply. Release cancels the native subscription.
final class NativeOperation: Sendable {
    let client: UInt64
    let id: UInt64
    private let released = Mutex(false)
    init(client: UInt64, id: UInt64) { self.client = client; self.id = id }
    @discardableResult func finish() -> Int32 {
        released.withLock { released in
            guard !released else { return 0 }
            let code = ramflux_v2_operation_release(client, id)
            // ABI release includes cancellation; failed admission must remain retryable.
            if code == 0 || code == 26 { released = true }
            return code
        }
    }
    deinit { finish() }
}
