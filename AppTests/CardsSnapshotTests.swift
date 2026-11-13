// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureCards
@MainActor final class CardsSnapshotTests: XCTestCase {
    func testGroupAuthorityAndMajorStates() {
        for (index, state) in CardsPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(CardsScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "cards-\(index)-\(scheme)", scheme: scheme, test: self)
        } }
    }
}
