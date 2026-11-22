// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureOnboarding
@MainActor final class OnboardingSnapshotTests: XCTestCase {
    func testAllOnboardingStatesRender() {
        for state in OnboardingPreviews.states {
            for scheme in [ColorScheme.light, .dark] {
                SnapshotCapture.record(OnboardingScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "\(state.stage.board)-\(scheme)", scheme: scheme, test: self)
            }
        }
    }
}
