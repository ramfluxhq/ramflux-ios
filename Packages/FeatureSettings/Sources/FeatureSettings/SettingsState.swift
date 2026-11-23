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
    public init(route: AppRoute = .settings) { self.route = route }
}
