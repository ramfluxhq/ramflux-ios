// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureSettings
@MainActor final class SettingsSnapshotTests: XCTestCase {
    func testSettingsDevicesAndBackupStates() {
        for (index, state) in SettingsPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(SettingsScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "settings-\(index)-\(scheme)", test: self)
        } }
    }
}
