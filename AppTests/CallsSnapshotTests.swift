// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureCalls
@MainActor final class CallsSnapshotTests: XCTestCase {
    func testCallHistorySignalingPermissionAndFailureStates() {
        for (index, state) in CallsPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(CallsScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "calls-\(index)-\(scheme)", scheme: scheme, test: self)
        } }
    }
    func testIncomingAndActiveWithExpandedCopyAndAccessibilityType() {
        for (index, state) in CallsPreviews.states.enumerated() where state.selected?.phase == .incomingRinging || state.selected?.phase == .active {
            for scheme in [ColorScheme.light, .dark] {
                SnapshotCapture.record(CallsScreen(state: state, onAction: { _ in }).dynamicTypeSize(.accessibility3), name: "calls-large-\(index)-\(scheme)", scheme: scheme, test: self)
            }
        }
    }
}
