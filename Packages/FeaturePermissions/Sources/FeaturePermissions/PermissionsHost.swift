// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct PermissionsHost: View {
    public let coordinator: PermissionsCoordinator
    public init(coordinator: PermissionsCoordinator) { self.coordinator = coordinator }
    public var body: some View {
        PermissionsScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
            .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
    }
}
/// One presenter sequences explanation dismissal before the OS prompt, without a timer.
public struct PermissionsPresentationHost: View {
    public let coordinator: PermissionsCoordinator
    public init(coordinator: PermissionsCoordinator) { self.coordinator = coordinator }
    private struct Sheet: Identifiable {
        let permission: DevicePermission
        let explanation: Bool
        var id: String { permission.rawValue + (explanation ? ":explain" : ":needed") }
    }
    private var sheet: Sheet? {
        if let permission = coordinator.viewModel.state.explanation { return Sheet(permission: permission, explanation: true) }
        if let permission = coordinator.viewModel.state.permissionNeeded { return Sheet(permission: permission, explanation: false) }
        return nil
    }
    public var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .sheet(item: Binding(get: { sheet }, set: { value in
                if value == nil, let current = sheet { coordinator.send(current.explanation ? .cancelExplanation : .dismissNeeded) }
            }), onDismiss: { coordinator.send(.explanationDismissed) }) { sheet in
                if sheet.explanation { PermissionsExplanation(permission: sheet.permission, busy: coordinator.viewModel.state.busy, onAction: coordinator.send) }
                else { PermissionNeededScreen(permission: sheet.permission, busy: coordinator.viewModel.state.busy, onAction: coordinator.send) }
            }
    }
}
