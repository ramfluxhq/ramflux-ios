// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
public enum SettingsPreviews {
    public static var states: [SettingsState] { [AppRoute.settings, .account, .devices, .device("web"), .nodes, .node("node"), .appearance, .privacy, .permissions, .about].map { route in
        var state = SettingsState(route: route)
        state.snapshot = SettingsSnapshot(accountID: "preview-account", devices: [DeviceRecord(id: "phone", isLocal: true, capabilities: ["Messages"]), DeviceRecord(id: "web", isLocal: false, capabilities: ["Messages"], webOrigin: "https://example.org")], nodes: [NodeRecord(id: "node", origin: "https://example.org", publicKey: "preview-key", isDefault: true)], retentionSeconds: 604800, requestPolicy: "manual")
        return state
    } }
}
#Preview("Settings") { SettingsScreen(state: SettingsState(), onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(SettingsPreviews.states.indices, id: \.self) { index in SettingsScreen(state: SettingsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(SettingsPreviews.states.indices, id: \.self) { index in SettingsScreen(state: SettingsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
/// Illustrative backup states for previews and review captures; never product data.
public enum BackupPreviews {
    public static var states: [BackupState] {
        let running = BackupRecord(id: "running", kind: "backup", state: "writing", sequence: 4, progress: .init(category: "messages", itemsDone: 120, itemsTotal: 400, bytesDone: 3_200_000, bytesTotal: 9_600_000))
        let done = BackupRecord(id: "done", kind: "backup", state: "done", sequence: 3, shareURL: URL(fileURLWithPath: "/preview/archive.rfb"))
        let verified = BackupRecord(id: "verified", kind: "restore", state: "verified", sequence: 2, accountID: "preview-account", merge: true, accountLabel: "Preview", archiveCreatedAt: 1_700_000_000)
        let failed = BackupRecord(id: "failed", kind: "backup", state: "failed", sequence: 1, failure: .init(code: "attachments_unavailable", unavailableCount: 2))
        var account = BackupState(account: "preview-account"); account.attended = true
        account.window = RowWindow(rows: [running, done, verified, failed], hasMore: false)
        var connecting = BackupState(account: nil)
        connecting.window = RowWindow(rows: [], hasMore: false)
        var restored = BackupState(account: nil); restored.step = .restored("preview-account")
        return [account, connecting, restored]
    }
}
