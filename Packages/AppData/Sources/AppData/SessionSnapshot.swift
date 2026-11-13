// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct SessionSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case stopped, opening, ready, suspended, unavailable(UnavailableReason), failed(AppFailure) }
    public let phase: Phase
    public let accounts: [AccountRecord]
    public let activeAccountID: String?
    public init(phase: Phase, accounts: [AccountRecord] = [], activeAccountID: String? = nil) {
        self.phase = phase; self.accounts = accounts; self.activeAccountID = activeAccountID
    }
}
