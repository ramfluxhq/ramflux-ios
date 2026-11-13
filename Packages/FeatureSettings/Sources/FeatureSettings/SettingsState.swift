// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public struct SettingsState: Equatable, Sendable {
    public var route: AppRoute
    public var snapshot = SettingsSnapshot()
    public var jobs: [BackupRecord] = []
    public var appearance: AppearanceMode = .system
    public var retentionSeconds: Int64 = 604800
    public var loading = false
    public var busy = false
    public var attended = false
    public var failure: AppFailure?
    public var pendingMutation: PendingSettingsMutation?
    public var unknownMutation = false
    public var pendingRevoke: DeviceRecord?
    public var backupIntent: BackupIntent?
    public var restoreHeld = false
    public var importSelecting = false
    public var shareURL: URL?
    public init(route: AppRoute = .settings) { self.route = route }
}
