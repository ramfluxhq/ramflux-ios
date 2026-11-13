// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureOnboarding
@MainActor final class OnboardingSnapshotTests: XCTestCase {
    func testAllOnboardingStatesRender() {
        for state in OnboardingPreviews.states {
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: OnboardingScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme).frame(width: 390, height: 844))
                let image = renderer.uiImage
                XCTAssertNotNil(image, state.stage.board)
                if let image { let attachment = XCTAttachment(image: image); attachment.name = "\(state.stage.board)-\(scheme)"; attachment.lifetime = .keepAlways; add(attachment) }
            }
        }
    }
}
