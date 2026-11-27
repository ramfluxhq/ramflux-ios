// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import SwiftUI
import UIKit

/// One editor of a secure entry form. `accountCode` accepts at most six ASCII digits on a number pad,
/// always runs left to right, and keeps the submit button disabled until it holds six digits.
public struct RFSecureEntryField: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case text, accountCode }
    public let id: String
    public let label: String
    public let kind: Kind
    public init(id: String, label: String, kind: Kind = .text) { self.id = id; self.label = label; self.kind = kind }
}

/// Secure entry form for secrets mixed with six-digit account codes. Editor strings are erased on
/// submit and on dismantle; the caller copies them into erasable buffers at once.
public struct RFSecureEntryForm: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let fields: [RFSecureEntryField]
    public let enabled: Bool
    /// False turns the fields off as well as the button (an account-code retry wait); typing is refused until it is true.
    public let fieldsEnabled: Bool
    public let submit: ([String: String]) -> Void
    public init(fields: [RFSecureEntryField], enabled: Bool, fieldsEnabled: Bool = true, submit: @escaping ([String: String]) -> Void) {
        self.fields = fields; self.enabled = enabled; self.fieldsEnabled = fieldsEnabled; self.submit = submit
    }
    public func makeUIView(context: Context) -> RFSecureEntryFormView { RFSecureEntryFormView(fields: fields, submit: submit) }
    public func updateUIView(_ view: RFSecureEntryFormView, context: Context) {
        view.button.setTitle(RFDesignStrings.text("kit.secret.confirmOnce", locale: locale), for: .normal)
        view.submit = submit; view.allowed = enabled; view.fieldsAllowed = fieldsEnabled; view.apply(theme)
    }
    public static func dismantleUIView(_ view: RFSecureEntryFormView, coordinator: ()) { view.erase() }
}

@MainActor public final class RFSecureEntryFormView: UIView, UITextFieldDelegate {
    static let codeDigits = 6
    let button = UIButton(type: .system)
    private var editors: [(RFSecureEntryField, UITextField)] = []
    var submit: ([String: String]) -> Void
    var allowed = true { didSet { refreshButton() } }
    var fieldsAllowed = true {
        didSet {
            guard fieldsAllowed != oldValue else { return }
            for (_, editor) in editors { editor.isEnabled = fieldsAllowed; if !fieldsAllowed { editor.text = ""; editor.resignFirstResponder() } }
            refreshButton()
        }
    }
    init(fields: [RFSecureEntryField], submit: @escaping ([String: String]) -> Void) {
        self.submit = submit; super.init(frame: .zero)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        for field in fields {
            let editor = UITextField(); editor.placeholder = field.label; editor.accessibilityLabel = field.label
            editor.isSecureTextEntry = true; editor.borderStyle = .roundedRect
            editor.autocorrectionType = .no; editor.spellCheckingType = .no; editor.autocapitalizationType = .none
            editor.adjustsFontForContentSizeCategory = true
            editor.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            if field.kind == .accountCode {
                editor.keyboardType = .asciiCapableNumberPad
                editor.semanticContentAttribute = .forceLeftToRight; editor.textAlignment = .left
                editor.delegate = self
                editor.addTarget(self, action: #selector(edited), for: .editingChanged)
            }
            editor.accessibilityIdentifier = "secure-entry-" + field.id
            editors.append((field, editor)); stack.addArrangedSubview(editor)
        }
        button.addTarget(self, action: #selector(commit), for: .touchUpInside)
        button.accessibilityIdentifier = "secure-entry-submit"
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; stack.addArrangedSubview(button); addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)])
        refreshButton()
    }
    func apply(_ theme: RFTheme) {
        let body = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: theme.font, size: theme.size_mobile_body) ?? .systemFont(ofSize: theme.size_mobile_body))
        for (field, editor) in editors {
            editor.textColor = UIColor(theme.text); editor.backgroundColor = UIColor(theme.input)
            editor.font = field.kind == .accountCode ? UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: theme.size_mobile_body, weight: .regular)) : body
        }
        button.tintColor = UIColor(theme.primary)
    }
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return false }
        let current = textField.text?.utf16.count ?? 0
        return current - range.length + string.utf16.count <= Self.codeDigits
    }
    @objc private func edited() { refreshButton() }
    private func refreshButton() {
        button.isEnabled = allowed && editors.allSatisfy { field, editor in field.kind != .accountCode || editor.text?.utf8.count == Self.codeDigits }
    }
    @objc private func commit() {
        let input = Dictionary(editors.map { ($0.0.id, $0.1.text ?? "") }, uniquingKeysWith: { _, last in last })
        erase(); submit(input)
    }
    func erase() { for (_, editor) in editors { editor.text = ""; editor.resignFirstResponder() }; refreshButton() }
    public required init?(coder: NSCoder) { return nil }
}
#endif
