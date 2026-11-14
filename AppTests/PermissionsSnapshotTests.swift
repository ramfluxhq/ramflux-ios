// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import AppData
import FeaturePermissions
@MainActor final class PermissionsSnapshotTests: XCTestCase {
    func testAllPermissionStatesExplanationsAndDeniedStatesInBothThemesAndLocales() {
        for scheme in [ColorScheme.light, .dark] {
            for (index, state) in PermissionsPreviews.states.enumerated() {
                SnapshotCapture.record(PermissionsScreen(state: state, onAction: { _ in }), name: "permissions-\(index)-\(scheme)", scheme: scheme, test: self)
            }
            for permission: DevicePermission in [.notifications, .microphone, .camera, .photoAdd] {
                SnapshotCapture.record(PermissionsExplanation(permission: permission, busy: false, onAction: { _ in }).environment(\.scenePhase, .active), name: "permission-explanation-\(permission)-\(scheme)", scheme: scheme, test: self)
                SnapshotCapture.record(PermissionNeededScreen(permission: permission, busy: false, onAction: { _ in }), name: "permission-denied-\(permission)-\(scheme)", scheme: scheme, test: self)
            }
        }
    }
}
