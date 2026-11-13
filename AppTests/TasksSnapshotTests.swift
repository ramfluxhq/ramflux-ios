// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureTasks
@MainActor final class TasksSnapshotTests: XCTestCase {
    func testTaskProgressPermissionAndFailureStates() {
        for (index, state) in TasksPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(TasksScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "tasks-\(index)-\(scheme)", scheme: scheme, test: self)
        } }
    }
    func testProposedAndActiveTaskFootersAtAccessibilityTypeSizes() {
        for (index, state) in TasksPreviews.states.enumerated() where state.selected?.status == "proposed" || state.selected?.status == "running" || state.selected?.status == "needs_me" {
            for scheme in [ColorScheme.light, .dark] {
                SnapshotCapture.record(TasksScreen(state: state, onAction: { _ in }).dynamicTypeSize(.accessibility3), name: "tasks-footer-large-\(index)-\(scheme)", scheme: scheme, test: self)
            }
        }
    }
}
