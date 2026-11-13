// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import RFDesign

public struct ChatComposer: UIViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    @Binding public var text: String
    public let enabled: Bool
    public let send: () -> Void
    public init(text: Binding<String>, enabled: Bool, send: @escaping () -> Void) { _text = text; self.enabled = enabled; self.send = send }
    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public func makeUIView(context: Context) -> ComposerView {
        let view = ComposerView()
        view.editor.delegate = context.coordinator
        view.button.addTarget(context.coordinator, action: #selector(Coordinator.sendMessage), for: .touchUpInside)
        return view
    }
    public func updateUIView(_ view: ComposerView, context: Context) {
        context.coordinator.parent = self
        // Do not replace marked text while an input method is composing.
        if view.editor.markedTextRange == nil, view.editor.text != text { view.editor.text = text }
        view.button.isEnabled = enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let theme = RFTheme.adaptive(scheme)
        view.backgroundColor = UIColor(theme.surface)
        view.editor.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: theme.font, size: theme.size_mobile_body) ?? .systemFont(ofSize: theme.size_mobile_body))
        view.editor.textColor = UIColor(theme.text)
        view.editor.backgroundColor = UIColor(theme.input)
        view.button.tintColor = UIColor(theme.primary)
        view.editor.layer.cornerRadius = theme.radius_input
    }
    @MainActor public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatComposer
        init(_ parent: ChatComposer) { self.parent = parent }
        public func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard let current = textView.text, let range = Range(range, in: current) else { return false }
            return current.replacingCharacters(in: range, with: text).utf8.count <= 65_536
        }
        @objc func sendMessage() { if parent.enabled { parent.send() } }
    }
}
#endif
