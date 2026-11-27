// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public struct SettingsState: Equatable, Sendable {
    public var route: AppRoute
    public var snapshot = SettingsSnapshot()
    public var appearance: AppearanceMode = .system
    public var retentionSeconds: Int64 = 604800
    public var loading = false
    public var busy = false
    public var attended = false
    public var failure: AppFailure?
    public var pendingMutation: PendingSettingsMutation?
    public var unknownMutation = false
    public var pendingRevoke: DeviceRecord?
    /// The confirmation for removing the account from this phone is open.
    public var confirmingRemoval = false
    /// The change-code sheet is open; `codeChanged` confirms a finished change.
    public var changingCode = false
    public var codeChanged = false
    /// This account's username status as the username directory reports it; nil until it has been read.
    public var username: UsernameStatus?
    /// The username status is being read.
    public var usernameLoading = false
    /// The claim sheet of the Username page; nil while it is closed.
    public var claim: UsernameClaim?
    /// The account's app lock as the SDK reports it; nil until the App lock page has read it.
    public var appLock: AppLockRecord?
    /// Core asked for the account code of a weakening change: the code sheet is open.
    public var codePrompt = false
    /// The moment the next account-code check is allowed (core's `code_retry_after_ms`, read on a monotonic clock); nil when no wait applies.
    public var codeRetryDeadline: ContinuousClock.Instant?
    /// The change that opened or is waiting for the code turns the lock off (otherwise it only lengthens the timeout).
    public var appLockTurningOff = false
    public init(route: AppRoute = .settings) { self.route = route }
}
