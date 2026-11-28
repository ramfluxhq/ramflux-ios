// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
@MainActor final class RFConfirmationActionsControl: UIView {
    let cancelButton = RFConfirmationCancelControl(type: .system)
    let confirmButton = RFConfirmationControl(type: .system)
    let stack = UIStackView()
    var cancelAction: () -> Void = {}
    private var needsInitialFocus = false
    /// A destructive confirmation starts with focus on Cancel; any other one starts on its primary action.
    var destructive = true
    /// Focus starts on Cancel for a destructive confirmation and for one that grants authority.
    var focusesCancel = true
    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [focusesCancel ? cancelButton : confirmButton] }
    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack); stack.addArrangedSubview(confirmButton); stack.addArrangedSubview(cancelButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            confirmButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        cancelButton.addTarget(self, action: #selector(cancelled), for: .touchUpInside)
        cancelButton.cancel = { [weak self] in self?.cancelled() }
        // The primary action is first on screen; for a destructive confirmation the safe action leads accessibility navigation.
        accessibilityElements = [cancelButton, confirmButton]
    }
    required init?(coder: NSCoder) { nil }
    @objc private func cancelled() { if cancelButton.isEnabled { cancelAction() } }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        needsInitialFocus = window != nil
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let target: UIButton = focusesCancel ? cancelButton : confirmButton
        guard needsInitialFocus, let window, window.windowScene?.activationState == .foregroundActive,
              !bounds.isEmpty, target.isEnabled else { return }
        // First-responder transfer is effective even when another branch owns keyboard input.
        // A setNeedsFocusUpdate() on this previously unfocused container is insufficient.
        guard target.becomeFirstResponder() else { return }
        needsInitialFocus = false
        if let system = UIFocusSystem.focusSystem(for: window) {
            system.requestFocusUpdate(to: target)
            system.updateFocusIfNeeded()
        }
        UIAccessibility.post(notification: .screenChanged, argument: target)
    }
}
#endif
