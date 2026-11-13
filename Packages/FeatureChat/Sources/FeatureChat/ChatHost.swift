// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ChatHost: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    public let coordinator: ChatCoordinator
    public init(coordinator: ChatCoordinator) { self.coordinator = coordinator }
    public var body: some View { ChatScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
        .onChange(of: phase) { _, value in coordinator.send(value == .active ? .appeared : .conceal) }
    }
}
