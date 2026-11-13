// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import RamfluxCore
@testable import AppData
import RFDesign
@testable import FeatureOnboarding
@testable import FeatureChat
@MainActor final class NativePresentationTests: XCTestCase {
    func testLiveRecoveryHostPropagatesLocaleAndAlternateTypographyWithoutCopyingStorage() throws {
        let bytes = Array("{\"code\":0,\"response\":{\"ok\":true,\"body\":{\"phrase\":\"alpha bravo\"}}}".utf8)
        let frame = try bytes.withUnsafeBytes { try SecretBytes(copying: $0) }
        let display = try RecoveryDisplay(frame)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "alternate-theme", withExtension: "json"))
        let alternate = try RFThemeRegistry.parse(Data(contentsOf: url)).tokens
        @MainActor func root(_ locale: String, _ theme: RFTheme) -> AnyView { AnyView(RecoveryPhraseView(display: display).environment(\.locale, Locale(identifier: locale)).environment(\.rfTheme, theme)) }
        let controller = UIHostingController(rootView: root("zh-CN", .light)); let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)); window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        defer { display.erase(); window.isHidden = true; window.rootViewController = nil }
        @MainActor func glyph(_ view: UIView) -> RecoveryGlyphView? { if let found = view as? RecoveryGlyphView { return found }; return view.subviews.lazy.compactMap { glyph($0) }.first }
        let first = try XCTUnwrap(glyph(controller.view))
        XCTAssertEqual(first.accessibilityLabel, FeatureOnboardingStrings.text("copy.043a01d16971", locale: Locale(identifier: "zh-CN"))); XCTAssertTrue(first.display === display)
        controller.rootView = root("en-XA", alternate); controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let updated = try XCTUnwrap(glyph(controller.view))
        XCTAssertTrue(updated.display === display); XCTAssertEqual(updated.fontName, DesignFonts.face(for: alternate.font_mono))
        XCTAssertEqual(updated.pointSize, UIFontMetrics(forTextStyle: .body).scaledValue(for: alternate.size_mobile_body))
        XCTAssertEqual(updated.accessibilityLabel, FeatureOnboardingStrings.text("copy.043a01d16971", locale: Locale(identifier: "en-XA")))
        display.erase(); var accessed = false; display.withDrawingBytes { _ in accessed = true }; XCTAssertFalse(accessed)
    }
    func testStationaryTimelineReconfiguresForHostPresentation() {
        let controller = TimelineController(), window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)); window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let records = [MessageRecord(id: "m", sender: "peer", kind: .deleted, isOwn: false)]
        controller.update(records, theme: .light, locale: Locale(identifier: "en")); controller.view.layoutIfNeeded()
        let previous = controller.presentationRevision
        controller.update(records, theme: .dark, locale: Locale(identifier: "zh-CN")); controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.presentationRevision, previous)
        let stable = controller.presentationRevision; controller.update(records, theme: .dark, locale: Locale(identifier: "zh-CN")); XCTAssertEqual(controller.presentationRevision, stable)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { controller.view.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image); attachment.name = "stationary-timeline-zh-dark"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
