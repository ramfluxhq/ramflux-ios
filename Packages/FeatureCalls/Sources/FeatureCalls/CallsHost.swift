// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public struct CallsHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: CallsCoordinator
    public init(coordinator: CallsCoordinator) { self.coordinator = coordinator }
    public var body: some View { CallsScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, phase in coordinator.send(phase == .active ? .appeared : .disappeared) }
    }
}
