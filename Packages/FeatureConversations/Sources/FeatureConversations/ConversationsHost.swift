// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ConversationsHost: View {
    @Environment(\.locale) private var locale
    public let coordinator: ConversationsCoordinator
    public init(coordinator: ConversationsCoordinator) { self.coordinator = coordinator }
    public var body: some View { ConversationsScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .onAppear { coordinator.send(.localeChanged(locale)); coordinator.send(.appeared) }
        .onChange(of: locale) { _, value in coordinator.send(.localeChanged(value)) }.onDisappear { coordinator.send(.disappeared) }
    }
}
