// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureTasks
@MainActor final class TasksSnapshotTests: XCTestCase {
    func testCallHistorySignalingPermissionAndFailureStates() {
        for (index, state) in TasksPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(TasksScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "tasks-\(index)-\(scheme)", scheme: scheme, test: self)
        } }
    }
}
