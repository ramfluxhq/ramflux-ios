// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
public enum SettingsPreviews {
    public static var states: [SettingsState] { [AppRoute.settings, .account, .devices, .device("web"), .nodes, .node("node"), .appearance, .privacy, .backup, .permissions, .about].map { route in
        var state = SettingsState(route: route)
        state.snapshot = SettingsSnapshot(accountID: "preview-account", devices: [DeviceRecord(id: "phone", isLocal: true, capabilities: ["Messages"]), DeviceRecord(id: "web", isLocal: false, capabilities: ["Messages"], webOrigin: "https://example.org")], nodes: [NodeRecord(id: "node", origin: "https://example.org", publicKey: "preview-key", isDefault: true)], retentionSeconds: 604800, requestPolicy: "manual")
        state.jobs = [BackupRecord(id: "verified-job", kind: "restore", state: "verified", sequence: 1, accountID: "preview-account", merge: true)]
        return state
    } }
}
#Preview("Settings") { SettingsScreen(state: SettingsState(), onAction: { _ in }) }
