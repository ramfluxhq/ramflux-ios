// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import FeatureOnboarding
@MainActor final class OnboardingSnapshotTests: XCTestCase {
    func testAllOnboardingStatesRender() {
        for state in OnboardingPreviews.states {
            for scheme in [ColorScheme.light, .dark] {
                let controller = UIHostingController(rootView: OnboardingScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.rootViewController = controller; window.makeKeyAndVisible()
                controller.view.frame = window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { controller.view.layer.render(in: $0.cgContext) }
                XCTAssertNotNil(image.cgImage, state.stage.board)
                let attachment = XCTAttachment(image: image); attachment.name = "\(state.stage.board)-\(scheme)"; attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }
}
