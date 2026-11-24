// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public struct CallsHost: View {
    public let coordinator: CallsCoordinator
    public init(coordinator: CallsCoordinator) { self.coordinator = coordinator }
    public var body: some View { CallsScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        .environment(\.callVideoAttacher, CallVideoAttacher { [viewModel = coordinator.viewModel] surface, slot, call in viewModel.attachVideo(surface, slot: slot, callID: call) })
        .onAppear { coordinator.send(.appeared) }.onDisappear { coordinator.send(.disappeared) }
    }
}
