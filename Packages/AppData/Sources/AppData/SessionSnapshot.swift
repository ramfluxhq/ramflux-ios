// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct SessionSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case stopped, opening, ready, suspended, unavailable(UnavailableReason), failed(AppFailure) }
    public let phase: Phase
    public let accounts: [AccountRecord]
    public let activeAccountID: String?
    /// The active account's app lock is engaged (its timeout passed while the app was away). The shell
    /// covers the account records until the account code is entered.
    public let appLocked: Bool
    /// The active account has the app lock on (as read when the app last went away or came back). While it is on,
    /// the shell covers the records from the return until the activation has read the lock.
    public let appLockEnabled: Bool
    public init(phase: Phase, accounts: [AccountRecord] = [], activeAccountID: String? = nil, appLocked: Bool = false, appLockEnabled: Bool = false) {
        self.phase = phase; self.accounts = accounts; self.activeAccountID = activeAccountID; self.appLocked = appLocked; self.appLockEnabled = appLockEnabled
    }
}
