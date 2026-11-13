// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
@MainActor final class RFConfirmationActionsControl: UIView {
    let cancelButton = UIButton(type: .system)
    let confirmButton = RFConfirmationControl(type: .system)
    let stack = UIStackView()
    var cancelAction: () -> Void = {}
    override var keyCommands: [UIKeyCommand]? { [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelled))] }
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
        // The safe action is first for both native focus and accessibility navigation.
        accessibilityElements = [cancelButton, confirmButton]
    }
    required init?(coder: NSCoder) { nil }
    @objc private func cancelled() { cancelAction() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            setNeedsFocusUpdate(); updateFocusIfNeeded()
            UIAccessibility.post(notification: .screenChanged, argument: cancelButton)
        }
    }
}
#endif
