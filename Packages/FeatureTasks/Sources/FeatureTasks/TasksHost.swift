// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public struct TasksHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: TasksCoordinator
    public init(coordinator: TasksCoordinator) { self.coordinator = coordinator }
    public var body: some View { TasksScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, phase in coordinator.send(phase == .active ? .appeared : .disappeared) }
    }
}
