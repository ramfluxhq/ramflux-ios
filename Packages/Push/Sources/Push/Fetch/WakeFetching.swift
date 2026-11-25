// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// The outcome of one wake fetch (the core's `ramflux_v2_wake_fetch`).
public enum WakeFetchOutcome: Sendable, Equatable {
    case fetched(Int), busy, locked, deadline
    /// The call failed or the core is unavailable; the code is the C ABI status.
    case failed(Int32)
}

/// Fetches the pending deliveries a wake names for one account, without decrypting or applying them.
public protocol WakeFetching: Sendable {
    func fetch(account: String, wakeID: String, deadline: ContinuousClock.Instant) async -> WakeFetchOutcome
}
