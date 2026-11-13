// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import CoreText
import AppData
import RFDesign

public struct SecureOnboardingForm: UIViewRepresentable {
    public let labels: [(String, String)]
    public let enabled: Bool
    public let submit: (SensitiveSubmission) -> Void
    public func makeUIView(context: Context) -> SecureFormView { SecureFormView(labels: labels, submit: submit) }
    public func updateUIView(_ view: SecureFormView, context: Context) { view.submit = submit; view.button.isEnabled = enabled }
    public static func dismantleUIView(_ view: SecureFormView, coordinator: ()) { view.erase() }
}
@MainActor public final class SecureFormView: UIView {
    let button = UIButton(type: .system)
    private var editors: [(String, UITextField)] = []
    var submit: (SensitiveSubmission) -> Void
    init(labels: [(String, String)], submit: @escaping (SensitiveSubmission) -> Void) {
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
        button.setTitle("Confirm once", for: .normal); button.addTarget(self, action: #selector(commit), for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; stack.addArrangedSubview(button); addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)])
    }
    @objc private func commit() {
        let input = SensitiveSubmission(values: Dictionary(editors.map { ($0.0, $0.1.text ?? "") }, uniquingKeysWith: { _, last in last }))
        erase(); submit(input)
    }
    func erase() { for (_, editor) in editors { editor.text = ""; editor.resignFirstResponder() } }
    public required init?(coder: NSCoder) { return nil }
}
public struct RecoveryPhraseView: UIViewRepresentable {
    public let display: RecoveryDisplay
    public func makeUIView(context: Context) -> RecoveryGlyphView { RecoveryGlyphView(display: display) }
    public func updateUIView(_ view: RecoveryGlyphView, context: Context) { view.display = display; view.setNeedsDisplay() }
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: RecoveryGlyphView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize
        let columns = width >= size * 20 ? 2 : 1
        return CGSize(width: width, height: CGFloat(24 / columns) * size * 1.6 + size)
    }
    public static func dismantleUIView(_ view: RecoveryGlyphView, coordinator: ()) { view.display = nil; view.setNeedsDisplay() }
}
@MainActor public final class RecoveryGlyphView: UIView {
    var display: RecoveryDisplay?
    init(display: RecoveryDisplay) {
        self.display = display; super.init(frame: .zero); backgroundColor = .clear
        isAccessibilityElement = true; accessibilityLabel = "Private recovery phrase display"
    }
    public required init?(coder: NSCoder) { return nil }
    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize
        let columns = bounds.width >= size * 20 ? 2 : 1
        let rows = 24 / columns
        let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
        context.setFillColor(UIColor.label.cgColor)
        display?.withDrawingBytes { raw in
            var column = 0, word = 0
            for byte in raw {
                if byte == 32 { word += 1; column = 0; continue }
                var character = UniChar(byte), glyph = CGGlyph(0)
                _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
                var point = CGPoint(x: CGFloat(word / rows) * bounds.width / CGFloat(columns) + CGFloat(column) * size * 0.62, y: bounds.height - size - CGFloat(word % rows) * size * 1.6)
                CTFontDrawGlyphs(font, &glyph, &point, 1, context); column += 1
            }
        }
    }
}
#endif
