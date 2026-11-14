// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum PermissionsPreviews {
    public static var states: [PermissionsState] {
        [DevicePermissionStatus.notAsked, .allowed, .limited, .restricted, .denied].map { status in
            var state = PermissionsState()
            state.snapshot = DevicePermissionsSnapshot(values: [.notifications: status, .camera: status, .photoAdd: status, .microphone: .notAsked, .files: .notRequired, .photoPicker: .notRequired, .incomingCalls: .unavailable, .background: .limited])
            return state
        }
    }
}
#Preview("Permissions") { RFThemeScope { PermissionsScreen(state: PermissionsPreviews.states[0], onAction: { _ in }) } }
#Preview("Permissions Chinese") { RFThemeScope { PermissionsScreen(state: PermissionsPreviews.states[3], onAction: { _ in }) }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Permissions expanded") { RFThemeScope { PermissionsScreen(state: PermissionsPreviews.states[2], onAction: { _ in }) }.environment(\.locale, Locale(identifier: "en-XA")) }
