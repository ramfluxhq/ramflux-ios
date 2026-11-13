// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct OnboardingHost: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    public let coordinator: OnboardingCoordinator
    public init(coordinator: OnboardingCoordinator) { self.coordinator = coordinator }
    private var securePresentation: AnyView? {
        #if os(iOS)
        if let id = coordinator.viewModel.state.displayID, let display = coordinator.secureSlot.presentation(for: id) { return AnyView(RecoveryPhraseView(display: display)) }
        #endif
        return nil
    }
    public var body: some View {
        OnboardingScreen(state: coordinator.viewModel.state, onAction: coordinator.send, securePresentation: securePresentation)
            .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
            .onChange(of: phase) { _, phase in if phase != .active { coordinator.send(.conceal) } }
    }
}
