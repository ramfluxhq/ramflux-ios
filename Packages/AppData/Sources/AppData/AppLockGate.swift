// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// The optional app lock (owner decision: off by default). With it off a return from the background
/// or a relaunch asks for nothing. The SDK side of the lock (arm with a timeout, lock now, presence or
/// code unlock) is not in the pinned core yet; when it lands its implementation answers here and the
/// shell covers the account records until it is passed.
public protocol AppLockGate: Sendable {
    var requiresUnlockOnReturn: Bool { get }
}

/// The default: no app lock.
public struct AppLockOff: AppLockGate {
    public init() {}
    public var requiresUnlockOnReturn: Bool { false }
}
