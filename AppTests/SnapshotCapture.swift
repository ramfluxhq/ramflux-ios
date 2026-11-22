// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import RFDesign
/// Review attachments for feature states over every CaptureMatrix locale and canvas.
/// Callers pass the theme and text size they vary.
@MainActor enum SnapshotCapture {
    static func record<V: View>(_ view: V, name: String, scheme: ColorScheme = .light, test: XCTestCase) {
        for locale in CaptureMatrix.locales {
            for canvas in CaptureMatrix.canvases {
                let controller = UIHostingController(rootView: RFThemeScope { NavigationStack { view } }
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, locale.locale)
                    .environment(\.layoutDirection, locale.layoutDirection))
                let window = UIWindow(frame: CGRect(origin: .zero, size: canvas.size))
                window.rootViewController = controller; window.makeKeyAndVisible()
                controller.view.frame = window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { controller.view.layer.render(in: $0.cgContext) }
                XCTAssertNotNil(image.cgImage, name)
                let item = XCTAttachment(image: image); item.name = "\(name)-\(locale.id)-\(canvas.width)"; item.lifetime = .keepAlways; test.add(item)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }
}
