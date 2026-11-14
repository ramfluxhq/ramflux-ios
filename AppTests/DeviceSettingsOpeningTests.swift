// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import UIKit
@testable import AppData
@MainActor final class DeviceSettingsOpeningTests: XCTestCase {
    func testInactiveSceneDefersWithoutDispatchingAURL() async {
        var calls = 0
        let opener = NativeDeviceSettingsOpener(activeScene: { nil }, openURL: { _, _ in calls += 1; return true })
        let app = await opener.open(.app), notifications = await opener.open(.notifications)
        XCTAssertEqual(app, .deferred); XCTAssertEqual(notifications, .deferred); XCTAssertEqual(calls, 0)
    }
    func testPublicRoutesCarryTheOriginatingActiveScene() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        var active: UIWindowScene?, urls: [URL] = []
        let opener = NativeDeviceSettingsOpener(activeScene: { active }, openURL: { origin, url in
            XCTAssertTrue(origin === scene); urls.append(url); return true
        })
        let deferred = await opener.open(.app); XCTAssertEqual(deferred, .deferred)
        active = scene
        let app = await opener.open(.app), notifications = await opener.open(.notifications)
        XCTAssertEqual(app, .opened); XCTAssertEqual(notifications, .opened)
        XCTAssertEqual(urls.map(\.absoluteString), [UIApplication.openSettingsURLString, UIApplication.openNotificationSettingsURLString])
    }
    func testSystemOpenRefusalIsAReportedFailure() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let opener = NativeDeviceSettingsOpener(activeScene: { scene }, openURL: { _, _ in false })
        let result = await opener.open(.app); XCTAssertEqual(result, .failed)
    }
}
