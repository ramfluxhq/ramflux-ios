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
    public var body: some View { SettingsScreen(state: coordinator.viewModel.state, onAction: coordinator.send).onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, value in coordinator.send(value == .active ? .appeared : .disappeared) }
    }
}
