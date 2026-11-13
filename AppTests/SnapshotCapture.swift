// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
@MainActor enum SnapshotCapture {
    static func record<V: View>(_ view: V, name: String, test: XCTestCase) {
        let controller = UIHostingController(rootView: NavigationStack { view })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.frame = window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { controller.view.layer.render(in: $0.cgContext) }
        XCTAssertNotNil(image.cgImage, name)
        let item = XCTAttachment(image: image); item.name = name; item.lifetime = .keepAlways; test.add(item)
        window.isHidden = true; window.rootViewController = nil
    }
}
