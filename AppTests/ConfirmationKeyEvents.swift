// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UIKit
/// Public UIKit event subclasses carry real key/phase/window/responder information.
/// No private HID injection or empty press events are used.
@MainActor final class ConfirmationTestKey: UIKey {
    private let usage: UIKeyboardHIDUsage
    private let text: String
    init(_ usage: UIKeyboardHIDUsage, text: String) { self.usage = usage; self.text = text; super.init() }
    required init?(coder: NSCoder) { nil }
    override var keyCode: UIKeyboardHIDUsage { usage }
    override var characters: String { text }
    override var charactersIgnoringModifiers: String { text }
    override var modifierFlags: UIKeyModifierFlags { [] }
}
@MainActor final class ConfirmationTestPress: UIPress {
    private let testKey: UIKey
    private let testPhase: UIPress.Phase
    private let testWindow: UIWindow
    private let testResponder: UIResponder
    init(key: UIKey, phase: UIPress.Phase, window: UIWindow, responder: UIResponder) {
        testKey = key; testPhase = phase; testWindow = window; testResponder = responder; super.init()
    }
    override var key: UIKey? { testKey }
    override var phase: UIPress.Phase { testPhase }
    override var window: UIWindow? { testWindow }
    override var responder: UIResponder? { testResponder }
}
@MainActor final class ConfirmationTestPressEvent: UIPressesEvent {
    private let presses: Set<UIPress>
    init(_ press: UIPress) { presses = [press]; super.init() }
    override var type: UIEvent.EventType { .presses }
    override var allPresses: Set<UIPress> { presses }
}
