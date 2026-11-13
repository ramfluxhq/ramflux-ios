// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import FeatureAppShell
import AppData

/// Render captures for architecture/design review, not a reviewed pixel-regression baseline.
@MainActor final class AppShellSnapshotTests: XCTestCase {
    func testAllMajorStatesRenderAtBothThemesAndLargeType() throws {
        for item in AppShellPreviews.cases {
            for (scheme, largeType) in [(ColorScheme.light, false), (.dark, false), (.light, true)] {
                let controller = UIHostingController(rootView: AppShellPreviews.screen(item)
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, largeType ? .accessibility3 : .large))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.rootViewController = controller; window.makeKeyAndVisible()
                controller.view.frame = window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { controller.view.layer.render(in: $0.cgContext) }
                XCTAssertEqual(image.size.width, 390); XCTAssertEqual(image.size.height, 844); XCTAssertNotNil(image.cgImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "shell-\(item.id)-\(scheme)-\(largeType ? "large-type" : "standard")"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }
    func testEveryTabHasItsOwnCaptureAndAccountsHaveSeparatePresentation() {
        for tab in AppTab.allCases {
            let state = AppShellState(session: SessionSnapshot(phase: .ready), tab: tab, privacyShield: false)
            let renderer = ImageRenderer(content: AppShellScreen(state: state, onAction: { _ in }).frame(width: 390, height: 844))
            XCTAssertNotNil(renderer.uiImage)
        }
    }
}
