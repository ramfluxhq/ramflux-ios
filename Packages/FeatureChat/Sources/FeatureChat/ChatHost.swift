// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureCards
import RFDesign
public struct ChatHost: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    public let coordinator: ChatCoordinator
    public init(coordinator: ChatCoordinator) { self.coordinator = coordinator }
    public var body: some View { ChatScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .environment(\.cardImageProvider, coordinator.cardImages)
        .onAppear { sendAppearance(); coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: colorScheme) { _, _ in sendAppearance() }
        .onChange(of: locale) { _, _ in sendAppearance() }
    }
    /// Cards are drawn in the host's colour scheme and locale; a change is sent so the visible cards are presented again.
    private func sendAppearance() {
        coordinator.send(.appearance(dark: colorScheme == .dark, locale: locale.identifier(.bcp47)))
    }
}
