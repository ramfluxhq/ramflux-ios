// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
/// An explicit keyboard responder, so Cancel can take input away from an outside editor.
@MainActor final class RFConfirmationCancelControl: UIButton {
    var cancel: () -> Void = {}
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelFromKeyboard))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }
    @objc private func cancelFromKeyboard() { if isEnabled { cancel() } }
}
#endif
