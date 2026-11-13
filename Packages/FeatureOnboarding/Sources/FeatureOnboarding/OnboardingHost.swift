// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct OnboardingHost: View {
    @Environment(\.scenePhase) private var phase
    public let coordinator: OnboardingCoordinator
    public init(coordinator: OnboardingCoordinator) { self.coordinator = coordinator }
    public var body: some View {
        OnboardingScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
            .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
            .onChange(of: phase) { _, phase in if phase != .active { coordinator.send(.conceal) } }
    }
}
