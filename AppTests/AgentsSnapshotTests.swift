// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureAgents
@MainActor final class AgentsSnapshotTests: XCTestCase {
    func testCallHistorySignalingPermissionAndFailureStates() {
        for (index, state) in AgentsPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(AgentsScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "agents-\(index)-\(scheme)", scheme: scheme, test: self)
        } }
    }
}
