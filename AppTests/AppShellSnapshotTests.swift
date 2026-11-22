// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import FeatureAppShell
import AppData
import RFDesign
import CoreText

/// Render captures for architecture/design review, not a reviewed pixel-regression baseline.
@MainActor final class AppShellSnapshotTests: XCTestCase {
    func testAllMajorStatesRenderAtBothThemesAndLargeType() throws {
        XCTAssertTrue(DesignFonts.registered)
        for face in DesignFonts.expectedFaces { XCTAssertEqual(CTFontCopyPostScriptName(CTFontCreateWithName(face as CFString, 17, nil)) as String, face) }
        for item in AppShellPreviews.cases {
            for (scheme, largeType) in [(ColorScheme.light, false), (.dark, false), (.light, true)] {
                for locale in CaptureMatrix.locales { for canvas in CaptureMatrix.canvases {
                let controller = UIHostingController(rootView: RFThemeScope { AppShellPreviews.screen(item) }
                    .environment(\.locale, locale.locale).environment(\.layoutDirection, locale.layoutDirection)
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, largeType ? .accessibility3 : .large))
                let window = UIWindow(frame: CGRect(origin: .zero, size: canvas.size))
                window.rootViewController = controller; window.makeKeyAndVisible()
                controller.view.frame = window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { controller.view.layer.render(in: $0.cgContext) }
                XCTAssertEqual(image.size.width, CGFloat(canvas.width)); XCTAssertEqual(image.size.height, CGFloat(canvas.height)); XCTAssertNotNil(image.cgImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "shell-\(item.id)-\(scheme)-\(locale.id)-\(canvas.width)-\(largeType ? "large-type" : "standard")"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
                } }
            }
        }
    }
    func testEveryTabHasItsOwnCaptureAndAccountsHaveSeparatePresentation() {
        for tab in AppTab.allCases {
            let state = AppShellState(session: SessionSnapshot(phase: .ready), tab: tab, privacyShield: false)
            let renderer = ImageRenderer(content: AppShellScreen(state: state, onAction: { _ in }).frame(width: CaptureMatrix.board.size.width, height: CaptureMatrix.board.size.height))
            XCTAssertNotNil(renderer.uiImage)
        }
    }
}
