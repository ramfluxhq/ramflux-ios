// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import UIKit
@testable import RFDesign
@MainActor final class ConfirmationControlTests: XCTestCase {
    func testCancelIsInitialNativeAndAccessibilityFocusTarget() throws {
        let view = RFConfirmationActionsControl()
        XCTAssertTrue(view.preferredFocusEnvironments.first === view.cancelButton)
        let first = try XCTUnwrap(view.accessibilityElements?.first as? UIButton)
        XCTAssertTrue(first === view.cancelButton)
        XCTAssertFalse(view.confirmButton.canBecomeFocused)
        XCTAssertEqual(view.keyCommands?.first?.input, UIKeyCommand.inputEscape)
        var cancelled = 0; var confirmed = 0
        view.cancelAction = { cancelled += 1 }; view.confirmButton.confirm = { confirmed += 1 }
        view.cancelButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(cancelled, 1); XCTAssertEqual(confirmed, 0)
    }
    func testNativeTapConfirmsOnceAndAccessibilityCannotRepeatIt() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController(); window.rootViewController = controller
        let button = RFConfirmationControl(type: .system)
        controller.view.addSubview(button); button.frame = CGRect(x: 0, y: 0, width: 200, height: 50)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        var count = 0; button.confirm = { count += 1 }
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        _ = button.accessibilityActivate()
        XCTAssertEqual(count, 1)
    }
    func testNativeKeyLifecycleNeverConfirmsAndDisabledAccessibilityDoesNotConsume() {
        let button = RFConfirmationControl(type: .system)
        var count = 0; button.confirm = { count += 1 }
        button.pressesBegan([], with: nil)
        button.pressesChanged([], with: nil)
        button.pressesChanged([], with: nil)
        button.pressesEnded([], with: nil)
        button.pressesCancelled([], with: nil)
        XCTAssertEqual(count, 0)
        button.isEnabled = false
        _ = button.accessibilityActivate()
        XCTAssertEqual(count, 0)
    }
}
