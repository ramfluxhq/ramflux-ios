// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
public struct SettingsHost: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    public let coordinator: SettingsCoordinator
    public init(coordinator: SettingsCoordinator) { self.coordinator = coordinator }
    public var body: some View {
        if coordinator.viewModel.state.route == .backup {
            BackupScreen(state: coordinator.backup.state, onAction: { coordinator.send($0) })
                .onAppear { coordinator.send(BackupAction.appeared) }.onDisappear { coordinator.send(BackupAction.disappeared) }
                .onChange(of: phase) { _, value in coordinator.send(value == .active ? BackupAction.appeared : BackupAction.disappeared) }
        } else if coordinator.viewModel.state.route == .pairDevice {
            // Leaving the app covers the invitation; only leaving the screen ends the ceremony.
            PairingScreen(state: coordinator.pairing.state, onAction: { coordinator.send($0) })
                .onAppear { coordinator.send(PairingAction.covered(phase != .active)); coordinator.send(PairingAction.appeared) }.onDisappear { coordinator.send(PairingAction.disappeared) }
                .onChange(of: phase) { _, value in coordinator.send(PairingAction.covered(value != .active)) }
        } else {
            SettingsScreen(state: coordinator.viewModel.state, onAction: { coordinator.send($0) }).onAppear { coordinator.send(SettingsAction.appeared) }.onDisappear { coordinator.send(SettingsAction.disappeared) }
                .onChange(of: phase) { _, value in coordinator.send(value == .active ? SettingsAction.appeared : SettingsAction.disappeared) }
        }
    }
}
