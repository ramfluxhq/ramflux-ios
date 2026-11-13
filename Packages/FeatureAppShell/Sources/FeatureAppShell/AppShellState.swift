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
    public init(session: SessionSnapshot = SessionSnapshot(phase: .stopped), tab: AppTab = .messages,
                privacyShield: Bool = true, busy: Bool = false, failure: AppFailure? = nil,
                unavailableFeature: UnavailableReason = .featureNotInstalled) {
        self.session = session; self.tab = tab; self.privacyShield = privacyShield
        self.busy = busy; self.failure = failure; self.unavailableFeature = unavailableFeature
    }
}
