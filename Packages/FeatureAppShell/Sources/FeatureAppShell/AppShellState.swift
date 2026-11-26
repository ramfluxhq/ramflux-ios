// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct AppShellState: Equatable, Sendable {
    public var session: SessionSnapshot
    public var tab: AppTab
    public var privacyShield: Bool
    public var busy: Bool
    public var failure: AppFailure?
    public var unavailableFeature: UnavailableReason
    /// The app lock is engaged: the lock screen (the account code) is shown over the covered shell.
    public var appLocked: Bool
    public init(session: SessionSnapshot = SessionSnapshot(phase: .stopped), tab: AppTab = .messages,
                privacyShield: Bool = true, busy: Bool = false, failure: AppFailure? = nil,
                unavailableFeature: UnavailableReason = .featureNotInstalled, appLocked: Bool = false) {
        self.session = session; self.tab = tab; self.privacyShield = privacyShield
        self.busy = busy; self.failure = failure; self.unavailableFeature = unavailableFeature; self.appLocked = appLocked
    }
}
