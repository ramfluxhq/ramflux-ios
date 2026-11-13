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
    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [cancelButton] }
    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack); stack.addArrangedSubview(cancelButton); stack.addArrangedSubview(confirmButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            confirmButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        cancelButton.addTarget(self, action: #selector(cancelled), for: .touchUpInside)
        cancelButton.cancel = { [weak self] in self?.cancelled() }
        // The safe action is first for both native focus and accessibility navigation.
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
        guard needsInitialFocus, let window, window.windowScene?.activationState == .foregroundActive,
              !bounds.isEmpty, cancelButton.isEnabled else { return }
        // First-responder transfer is effective even when another branch owns keyboard input.
        // A setNeedsFocusUpdate() on this previously unfocused container is insufficient.
        guard cancelButton.becomeFirstResponder() else { return }
        needsInitialFocus = false
        if let system = UIFocusSystem.focusSystem(for: window) {
            system.requestFocusUpdate(to: cancelButton)
            system.updateFocusIfNeeded()
        }
        UIAccessibility.post(notification: .screenChanged, argument: cancelButton)
    }
}
#endif
