// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import RFDesign

@MainActor public final class ComposerView: UIView {
    let editor = UITextView()
    let button = UIButton(type: .system)
    public init() {
        super.init(frame: .zero)
        editor.font = UIFont.preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.accessibilityLabel = "Message"
        editor.accessibilityIdentifier = "chat-draft"
        button.setTitle("Send", for: .normal); button.accessibilityIdentifier = "chat-send"
        let stack = UIStackView(arrangedSubviews: [editor, button])
        stack.alignment = .center; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        editor.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            editor.heightAnchor.constraint(equalTo: stack.heightAnchor), editor.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 52), button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }
    public required init?(coder: NSCoder) { return nil }
}
#endif
