// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// The prepare step of a username change, kept admitted until its authorization has returned: the core
/// refuses `ramflux_v2_username_authorize` for a released or cancelled parent. Release it exactly once,
/// after the authorization (or when the change is abandoned).
public final class UsernameDraftOperation: Sendable {
    let native: NativeOperation
    /// The C ABI operation id the core echoes as `request_id` of the authorization.
    public var requestID: UInt64 { native.id }
    init(native: NativeOperation) { self.native = native }
    /// Releases the prepare operation. Safe to call more than once.
    public func release() { native.finish() }
}
