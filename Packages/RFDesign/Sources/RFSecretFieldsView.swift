// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import SwiftUI
import UIKit
@MainActor public final class RFSecretFieldsView: UIView {
    let button = UIButton(type: .system)
    private var editors: [(String, UITextField)] = []
    var submit: ([String: String]) -> Void
    init(labels: [(String, String)], submit: @escaping ([String: String]) -> Void) {
        self.submit = submit; super.init(frame: .zero)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        for (id, label) in labels {
            let field = UITextField(); field.placeholder = label; field.accessibilityLabel = label
            field.isSecureTextEntry = true; field.borderStyle = .roundedRect
            field.autocorrectionType = .no; field.spellCheckingType = .no; field.autocapitalizationType = .none
            field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            editors.append((id, field)); stack.addArrangedSubview(field)
        }
        button.setTitle(RFDesignStrings.text("copy.a2538eaa411f"), for: .normal); button.addTarget(self, action: #selector(commit), for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; stack.addArrangedSubview(button); addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)])
    }
    func apply(_ theme: RFTheme) {
        for (_, editor) in editors {
            editor.textColor = UIColor(theme.text); editor.backgroundColor = UIColor(theme.input)
            editor.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: theme.font, size: theme.size_mobile_body) ?? .systemFont(ofSize: theme.size_mobile_body))
        }
        button.tintColor = UIColor(theme.primary)
    }
    @objc private func commit() {
        let input = Dictionary(editors.map { ($0.0, $0.1.text ?? "") }, uniquingKeysWith: { _, last in last })
        erase(); submit(input)
    }
    func erase() { for (_, editor) in editors { editor.text = ""; editor.resignFirstResponder() } }
    public required init?(coder: NSCoder) { return nil }
}
#endif
