// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public struct DeliveryHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: DeliveryCoordinator
    public init(coordinator: DeliveryCoordinator) { self.coordinator = coordinator }
    public var body: some View {
        DeliveryScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
            .onAppear { coordinator.send(.appeared) }
            .onChange(of: phase) { _, phase in if phase == .active { coordinator.send(.foreground) } }
    }
}
