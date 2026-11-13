// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import SwiftUI
import UIKit
public struct RFSecretFields: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let labels: [(String, String)]
    public let enabled: Bool
    public let submit: ([String: String]) -> Void
    public init(labels: [(String, String)], enabled: Bool, submit: @escaping ([String: String]) -> Void) { self.labels = labels; self.enabled = enabled; self.submit = submit }
    public func makeUIView(context: Context) -> RFSecretFieldsView { RFSecretFieldsView(labels: labels, submit: submit) }
    public func updateUIView(_ view: RFSecretFieldsView, context: Context) {
        view.button.setTitle(RFDesignStrings.text("copy.a2538eaa411f", locale: locale), for: .normal)
        view.submit = submit; view.button.isEnabled = enabled; view.apply(theme)
    }
    public static func dismantleUIView(_ view: RFSecretFieldsView, coordinator: ()) { view.erase() }
}
#endif
