// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public struct AgentsHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: AgentsCoordinator
    public init(coordinator: AgentsCoordinator) { self.coordinator = coordinator }
    public var body: some View { AgentsScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, phase in coordinator.send(phase == .active ? .appeared : .disappeared) }
    }
}
