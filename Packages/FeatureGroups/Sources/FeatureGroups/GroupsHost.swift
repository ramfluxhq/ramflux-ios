// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public struct GroupsHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: GroupsCoordinator
    public init(coordinator: GroupsCoordinator) { self.coordinator = coordinator }
    public var body: some View { GroupsScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, value in coordinator.send(value == .active ? .appeared : .disappeared) }
    }
}
