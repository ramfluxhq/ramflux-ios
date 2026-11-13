// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
/// UIButton keyboard activation is suppressed at the native responder boundary, including key-up.
@MainActor final class RFConfirmationControl: UIButton {
    var confirm: () -> Void = {}
    private var gate = RFConfirmationGate()
    override var canBecomeFocused: Bool { false }
    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func tapped() { activate(.tap) }
    private func activate(_ source: RFConfirmationGate.Source) {
        if gate.activate(source, enabled: isEnabled && window?.windowScene?.activationState == .foregroundActive) { confirm() }
    }
    override func accessibilityActivate() -> Bool {
        activate(.accessibility)
        return true
    }
    override func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        guard event?.type != .presses else { return }
        super.sendAction(action, to: target, for: event)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}
    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}
}
#endif
