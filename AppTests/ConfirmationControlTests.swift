// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
@testable import RFDesign
@MainActor final class ConfirmationControlTests: XCTestCase {
    private func host() throws -> (UIWindow, UIViewController, UITextField) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController(); window.rootViewController = controller; window.makeKeyAndVisible()
        let outside = UITextField(frame: CGRect(x: 20, y: 60, width: 260, height: 48))
        controller.view.addSubview(outside)
        XCTAssertTrue(outside.becomeFirstResponder()); XCTAssertTrue(outside.isFirstResponder)
        return (window, controller, outside)
    }
    private func mount(_ actions: RFConfirmationActionsControl, in controller: UIViewController) {
        actions.frame = CGRect(x: 20, y: 160, width: 300, height: 140)
        controller.view.addSubview(actions)
        controller.view.layoutIfNeeded(); actions.layoutIfNeeded()
    }
    private func escape(window: UIWindow, responder: UIResponder) throws -> Bool {
        let command = try XCTUnwrap(responder.keyCommands?.first { $0.input == UIKeyCommand.inputEscape })
        let key = ConfirmationTestKey(.keyboardEscape, text: UIKeyCommand.inputEscape)
        let press = ConfirmationTestPress(key: key, phase: .began, window: window, responder: responder)
        return UIApplication.shared.sendAction(try XCTUnwrap(command.action), to: nil, from: command, for: ConfirmationTestPressEvent(press))
    }
    func testInlineReviewTakesCancelKeyboardFocusFromOutsideAndRoutesEscape() throws {
        let (window, controller, outside) = try host()
        defer { window.isHidden = true; window.rootViewController = nil }
        let actions = RFConfirmationActionsControl(); var cancelled = 0; var confirmed = 0
        actions.cancelAction = { cancelled += 1 }; actions.confirmButton.confirm = { confirmed += 1 }
        mount(actions, in: controller)
        XCTAssertFalse(outside.isFirstResponder)
        XCTAssertTrue(actions.cancelButton.isFirstResponder)
        XCTAssertTrue(try escape(window: window, responder: actions.cancelButton))
        XCTAssertEqual(cancelled, 1); XCTAssertEqual(confirmed, 0)
        XCTAssertTrue(try XCTUnwrap(actions.accessibilityElements?.first as? UIButton) === actions.cancelButton)
    }
    func testModalReviewTakesCancelKeyboardFocusFromExistingEditorAndRoutesEscape() async throws {
        let (window, controller, outside) = try host()
        defer { window.isHidden = true; window.rootViewController = nil }
        let modal = UIViewController(); modal.modalPresentationStyle = .formSheet
        await withCheckedContinuation { continuation in controller.present(modal, animated: false) { continuation.resume() } }
        let actions = RFConfirmationActionsControl(); var cancelled = 0
        actions.cancelAction = { cancelled += 1 }
        mount(actions, in: modal)
        XCTAssertFalse(outside.isFirstResponder)
        XCTAssertTrue(actions.cancelButton.isFirstResponder)
        XCTAssertTrue(try escape(window: window, responder: actions.cancelButton))
        XCTAssertEqual(cancelled, 1)
        await withCheckedContinuation { continuation in modal.dismiss(animated: false) { continuation.resume() } }
    }
    func testEnabledHostedConfirmRejectsReturnSpaceDownRepeatUpThenAcceptsTapOnce() throws {
        let (window, controller, _) = try host()
        defer { window.isHidden = true; window.rootViewController = nil }
        let actions = RFConfirmationActionsControl(); mount(actions, in: controller)
        let button = actions.confirmButton; var confirmed = 0; button.confirm = { confirmed += 1 }
        XCTAssertTrue(button.isEnabled); XCTAssertTrue(button.window === window)
        XCTAssertEqual(window.windowScene?.activationState, .foregroundActive)
        let target = try XCTUnwrap(button.allTargets.first).base
        let action = NSSelectorFromString(try XCTUnwrap(button.actions(forTarget: target, forControlEvent: .touchUpInside)?.first))
        for (usage, text): (UIKeyboardHIDUsage, String) in [(.keyboardReturnOrEnter, "\r"), (.keyboardSpacebar, " ")] {
            let key = ConfirmationTestKey(usage, text: text)
            for phase: UIPress.Phase in [.began, .changed, .stationary, .ended] {
                let press = ConfirmationTestPress(key: key, phase: phase, window: window, responder: button)
                let event = ConfirmationTestPressEvent(press)
                XCTAssertFalse(event.allPresses.isEmpty)
                switch phase {
                case .began: button.pressesBegan([press], with: event)
                case .ended: button.pressesEnded([press], with: event)
                default: button.pressesChanged([press], with: event)
                }
                // Exercise UIControl's keyboard action dispatch as well as responder phases.
                // Removing the event rejection activates this same live, enabled instance.
                button.sendAction(action, to: target, for: event)
                XCTAssertEqual(confirmed, 0)
            }
        }
        button.sendActions(for: .touchUpInside); XCTAssertEqual(confirmed, 1)
        _ = button.accessibilityActivate(); button.sendActions(for: .touchUpInside); XCTAssertEqual(confirmed, 1)
    }
    func testEnabledHostedAccessibilityCanConfirmAfterKeyboardEvents() throws {
        let (window, controller, _) = try host()
        defer { window.isHidden = true; window.rootViewController = nil }
        let actions = RFConfirmationActionsControl(); mount(actions, in: controller)
        var confirmed = 0; actions.confirmButton.confirm = { confirmed += 1 }
        let key = ConfirmationTestKey(.keyboardSpacebar, text: " ")
        let press = ConfirmationTestPress(key: key, phase: .ended, window: window, responder: actions.confirmButton)
        actions.confirmButton.pressesEnded([press], with: ConfirmationTestPressEvent(press))
        _ = actions.confirmButton.accessibilityActivate(); XCTAssertEqual(confirmed, 1)
        _ = actions.confirmButton.accessibilityActivate(); XCTAssertEqual(confirmed, 1)
    }
    func testRenderedNativeConfirmHasLocalizedActionSummary() throws {
        for (locale, summary, expected) in [("en", "Revoke device · phone", "Confirm: Revoke device · phone"), ("zh-CN", "撤销设备 · 手机", "确认：撤销设备 · 手机")] {
            let (window, controller, _) = try host()
            defer { window.isHidden = true; window.rootViewController = nil }
            let hosting = UIHostingController(rootView: RFThemeScope {
                RFHostConfirmationActions(summary: summary, enabled: true, confirm: {}, cancel: {})
            }.environment(\.locale, Locale(identifier: locale)).environment(\.scenePhase, .active))
            controller.addChild(hosting); hosting.view.frame = CGRect(x: 0, y: 150, width: 350, height: 180)
            controller.view.addSubview(hosting.view); hosting.didMove(toParent: controller)
            hosting.view.layoutIfNeeded()
            func find(_ view: UIView) -> RFConfirmationControl? {
                if let button = view as? RFConfirmationControl { return button }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            let button = try XCTUnwrap(find(hosting.view))
            XCTAssertEqual(button.accessibilityLabel, expected)
            XCTAssertEqual(button.configuration?.title, locale == "en" ? "Confirm" : "确认")
            XCTAssertTrue(button.isEnabled)
        }
    }
}
