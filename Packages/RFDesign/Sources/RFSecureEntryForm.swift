// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import SwiftUI
import UIKit

/// One editor of a secure entry form. `accountCode` accepts at most six ASCII digits on a number pad,
/// always runs left to right, and keeps the submit button disabled until it holds six digits. A `text` editor
/// is masked and has a Show toggle of its own; it never autocorrects, suggests or learns.
public struct RFSecureEntryField: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case text, accountCode }
    public let id: String
    public let label: String
    public let kind: Kind
    /// The id of the field this one repeats: while both hold six digits and differ, the step cannot continue.
    public let repeats: String?
    public init(id: String, label: String, kind: Kind = .text, repeats: String? = nil) { self.id = id; self.label = label; self.kind = kind; self.repeats = repeats }
}

/// One page of a secure entry form: a title, labelled editors, a helper line under them, a notice above the button
/// and the button's own label. A form of several steps keeps every editor's text inside its editors only; nothing
/// crosses a step through any other object.
public struct RFSecureEntryStep: Sendable, Equatable {
    public let title: String?
    public let fields: [RFSecureEntryField]
    public let helper: String?
    public let notice: String?
    public let actionLabel: String
    public init(title: String? = nil, fields: [RFSecureEntryField], helper: String? = nil, notice: String? = nil, actionLabel: String) {
        self.title = title; self.fields = fields; self.helper = helper; self.notice = notice; self.actionLabel = actionLabel
    }
}

/// Secure entry form for secrets mixed with six-digit account codes. Editor strings are erased on
/// submit and on dismantle; the caller copies them into erasable buffers at once.
public struct RFSecureEntryForm: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let steps: [RFSecureEntryStep]
    public let enabled: Bool
    /// False turns the fields off as well as the button (an account-code retry wait); typing is refused until it is true.
    public let fieldsEnabled: Bool
    /// The one status line under the fields (a wrong code, a wait); a mismatch between two code fields takes its place.
    public let status: String?
    public let mismatchMessage: String?
    /// Called when the user starts typing, so the caller can clear a stale status.
    public let onEdit: (() -> Void)?
    public let submit: ([String: String]) -> Void
    public init(steps: [RFSecureEntryStep], enabled: Bool, fieldsEnabled: Bool = true, status: String? = nil, mismatchMessage: String? = nil,
                onEdit: (() -> Void)? = nil, submit: @escaping ([String: String]) -> Void) {
        self.steps = steps; self.enabled = enabled; self.fieldsEnabled = fieldsEnabled; self.status = status
        self.mismatchMessage = mismatchMessage; self.onEdit = onEdit; self.submit = submit
    }
    public init(fields: [RFSecureEntryField], submitLabel: String, enabled: Bool, fieldsEnabled: Bool = true, status: String? = nil, onEdit: (() -> Void)? = nil,
                submit: @escaping ([String: String]) -> Void) {
        self.init(steps: [RFSecureEntryStep(fields: fields, actionLabel: submitLabel)], enabled: enabled, fieldsEnabled: fieldsEnabled, status: status, onEdit: onEdit, submit: submit)
    }
    public func makeUIView(context: Context) -> RFSecureEntryFormView { RFSecureEntryFormView(steps: steps, submit: submit) }
    public func updateUIView(_ view: RFSecureEntryFormView, context: Context) {
        view.submit = submit; view.onEdit = onEdit; view.mismatchMessage = mismatchMessage
        view.status = status; view.allowed = enabled; view.fieldsAllowed = fieldsEnabled
        view.apply(theme, locale: locale)
    }
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: RFSecureEntryFormView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }
    public static func dismantleUIView(_ view: RFSecureEntryFormView, coordinator: ()) { view.erase() }
}

@MainActor public final class RFSecureEntryFormView: UIView, UITextFieldDelegate {
    static let codeDigits = 6
    private struct Editor { let field: RFSecureEntryField; let editor: UITextField; let step: Int; let toggle: UIButton? }
    private let primaryButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var stepBlocks: [UIStackView] = []
    private var titleLabels: [UILabel] = []
    private var captions: [UILabel] = []
    private var helperLabels: [UILabel] = []
    private var noticeLabels: [UILabel] = []
    private var editors: [Editor] = []
    private let steps: [RFSecureEntryStep]
    private var step = 0 { didSet { showStep() } }
    private var theme: RFTheme?
    private var locale = Locale.current
    var submit: ([String: String]) -> Void
    var onEdit: (() -> Void)?
    var mismatchMessage: String? { didSet { refreshButton() } }
    var status: String? { didSet { refreshStatus() } }
    var allowed = true { didSet { refreshButton() } }
    var fieldsAllowed = true {
        didSet {
            guard fieldsAllowed != oldValue else { return }
            for item in editors { item.editor.isEnabled = fieldsAllowed; if !fieldsAllowed { item.editor.text = ""; item.editor.resignFirstResponder() } }
            refreshButton()
        }
    }
    init(steps: [RFSecureEntryStep], submit: @escaping ([String: String]) -> Void) {
        self.steps = steps; self.submit = submit; super.init(frame: .zero)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, page) in steps.enumerated() {
            let block = UIStackView(); block.axis = .vertical; block.spacing = 12
            if page.title != nil {
                let title = UILabel(); title.numberOfLines = 0; title.accessibilityTraits = .header; title.text = page.title
                title.accessibilityIdentifier = "secure-entry-step-title-\(index)"
                titleLabels.append(title); block.addArrangedSubview(title)
            }
            for field in page.fields {
                let item = UIStackView(); item.axis = .vertical; item.spacing = 4
                let caption = UILabel(); caption.numberOfLines = 0; caption.text = field.label; caption.isAccessibilityElement = false
                caption.accessibilityIdentifier = "secure-entry-label-" + field.id
                captions.append(caption)
                let editor = UITextField(); editor.placeholder = nil; editor.accessibilityLabel = field.label
                editor.isSecureTextEntry = true; editor.borderStyle = .roundedRect
                editor.autocorrectionType = .no; editor.spellCheckingType = .no; editor.autocapitalizationType = .none
                editor.smartQuotesType = .no; editor.smartDashesType = .no; editor.smartInsertDeleteType = .no
                editor.inlinePredictionType = .no; editor.textContentType = nil
                editor.adjustsFontForContentSizeCategory = true
                editor.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                editor.addTarget(self, action: #selector(edited), for: .editingChanged)
                var toggle: UIButton?
                if field.kind == .accountCode {
                    editor.keyboardType = .asciiCapableNumberPad
                    editor.semanticContentAttribute = .forceLeftToRight; editor.textAlignment = .left
                    editor.delegate = self
                } else {
                    editor.keyboardType = .asciiCapable
                    let show = UIButton(type: .system); show.addTarget(self, action: #selector(toggled(_:)), for: .touchUpInside)
                    show.accessibilityIdentifier = "secure-entry-show-" + field.id
                    editor.rightView = show; editor.rightViewMode = .always; toggle = show
                }
                editor.accessibilityIdentifier = "secure-entry-" + field.id
                editors.append(Editor(field: field, editor: editor, step: index, toggle: toggle))
                item.addArrangedSubview(caption); item.addArrangedSubview(editor); block.addArrangedSubview(item)
            }
            let helper = UILabel(); helper.numberOfLines = 0; helper.text = page.helper; helper.isHidden = page.helper == nil
            helper.accessibilityIdentifier = "secure-entry-helper-\(index)"
            helperLabels.append(helper); block.addArrangedSubview(helper)
            stepBlocks.append(block); stack.addArrangedSubview(block)
        }
        statusLabel.numberOfLines = 0; statusLabel.accessibilityIdentifier = "secure-entry-status"; statusLabel.isHidden = true
        stack.addArrangedSubview(statusLabel)
        for (index, page) in steps.enumerated() {
            let notice = UILabel(); notice.numberOfLines = 0; notice.text = page.notice; notice.isHidden = true
            notice.accessibilityIdentifier = "secure-entry-notice-\(index)"
            noticeLabels.append(notice); stack.addArrangedSubview(notice)
        }
        primaryButton.addTarget(self, action: #selector(commit), for: .touchUpInside)
        primaryButton.accessibilityIdentifier = "secure-entry-submit"
        primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; stack.addArrangedSubview(primaryButton)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.accessibilityIdentifier = "secure-entry-back"
        backButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; stack.addArrangedSubview(backButton)
        addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)])
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardShown), name: UIResponder.keyboardDidShowNotification, object: nil)
        showStep()
    }
    func apply(_ theme: RFTheme, locale: Locale) {
        self.theme = theme; self.locale = locale
        let scale = { (size: CGFloat, style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont in
            UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(name: theme.font, size: size) ?? .systemFont(ofSize: size, weight: weight))
        }
        for label in titleLabels { label.font = scale(theme.size_title, .title3, .semibold); label.textColor = UIColor(theme.text); label.adjustsFontForContentSizeCategory = true }
        for label in captions { label.font = scale(theme.size_secondary, .subheadline, .medium); label.textColor = UIColor(theme.text); label.adjustsFontForContentSizeCategory = true }
        for label in helperLabels + noticeLabels { label.font = scale(theme.size_secondary, .footnote, .regular); label.textColor = UIColor(theme.secondary); label.adjustsFontForContentSizeCategory = true }
        statusLabel.font = scale(theme.size_secondary, .subheadline, .medium); statusLabel.adjustsFontForContentSizeCategory = true
        let body = scale(theme.size_mobile_body, .body, .regular)
        for item in editors {
            item.editor.textColor = UIColor(theme.text); item.editor.backgroundColor = UIColor(theme.input)
            item.editor.font = item.field.kind == .accountCode ? UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: theme.size_mobile_body, weight: .regular)) : body
            if let toggle = item.toggle {
                var config = UIButton.Configuration.plain()
                config.title = RFDesignStrings.text(item.editor.isSecureTextEntry ? "kit.secret.show" : "kit.secret.hide", locale: locale)
                config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
                config.baseForegroundColor = UIColor(theme.primary)
                config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var result = attributes; result.font = scale(theme.size_secondary, .subheadline, .medium); return result
                }
                toggle.configuration = config
                toggle.sizeToFit()
            }
        }
        backButton.tintColor = UIColor(theme.primary); backButton.titleLabel?.font = scale(theme.size_mobile_body, .body, .semibold)
        backButton.setTitle(RFDesignStrings.text("kit.back", locale: locale), for: .normal)
        primaryButton.tintColor = UIColor(theme.primary)
        primaryButton.configurationUpdateHandler = { [weak self] button in
            guard let self, let theme = self.theme else { return }
            var config = UIButton.Configuration.filled()
            config.title = self.steps[self.step].actionLabel
            config.cornerStyle = .fixed
            config.background.cornerRadius = theme.radius_button
            config.baseBackgroundColor = UIColor(button.isEnabled ? theme.primary : theme.surface)
            config.baseForegroundColor = UIColor(button.isEnabled ? theme.on_primary : theme.control)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = scale(theme.size_mobile_body, .body, .semibold); return result
            }
            button.configuration = config
        }
        primaryButton.setNeedsUpdateConfiguration()
        refreshStatus()
    }
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return false }
        let current = textField.text?.utf16.count ?? 0
        return current - range.length + string.utf16.count <= Self.codeDigits
    }
    @objc private func edited() { onEdit?(); refreshButton() }
    @objc private func toggled(_ button: UIButton) {
        guard let item = editors.first(where: { $0.toggle === button }) else { return }
        let text = item.editor.text
        item.editor.isSecureTextEntry.toggle()
        // Switching the masking mid-edit would otherwise drop the text on the next keystroke.
        item.editor.text = nil; item.editor.text = text
        if let theme { apply(theme, locale: locale) }
    }
    @objc private func keyboardShown() {
        guard editors.contains(where: { $0.editor.isFirstResponder }) else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        (ancestor as? UIScrollView)?.scrollRectToVisible(convert(bounds, to: ancestor), animated: true)
    }
    private var current: [Editor] { editors.filter { $0.step == step } }
    private var mismatched: Bool {
        for item in current {
            guard let other = item.field.repeats, let peer = editors.first(where: { $0.field.id == other }) else { continue }
            let a = item.editor.text ?? "", b = peer.editor.text ?? ""
            if a.utf8.count == Self.codeDigits, b.utf8.count == Self.codeDigits, a != b { return true }
        }
        return false
    }
    private func showStep() {
        for (index, block) in stepBlocks.enumerated() { block.isHidden = index != step }
        for (index, label) in noticeLabels.enumerated() { label.isHidden = index != step || label.text == nil }
        backButton.isHidden = step == 0
        primaryButton.setNeedsUpdateConfiguration()
        refreshButton()
    }
    private func refreshStatus() {
        let shown = (mismatched ? mismatchMessage : nil) ?? status
        statusLabel.text = shown; statusLabel.isHidden = shown == nil
        if let theme { statusLabel.textColor = UIColor(mismatched ? theme.danger : theme.secondary) }
    }
    private func refreshButton() {
        let complete = current.allSatisfy { item in
            item.field.kind == .accountCode ? item.editor.text?.utf8.count == Self.codeDigits : !(item.editor.text ?? "").isEmpty
        }
        primaryButton.isEnabled = allowed && fieldsAllowed && complete && !mismatched
        refreshStatus()
    }
    @objc private func goBack() { if step > 0 { step -= 1 } }
    @objc private func commit() {
        guard primaryButton.isEnabled else { return }
        if step < steps.count - 1 { step += 1; refreshButton(); return }
        let input = Dictionary(editors.map { ($0.field.id, $0.editor.text ?? "") }, uniquingKeysWith: { _, last in last })
        erase(); submit(input)
    }
    func erase() {
        for item in editors { item.editor.text = ""; item.editor.isSecureTextEntry = true; item.editor.resignFirstResponder() }
        step = 0
        refreshButton()
    }
    public required init?(coder: NSCoder) { return nil }
}
#endif
