// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import SwiftUI
import UIKit
struct RFNativeConfirmationActions: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let summary: String
    let enabled: Bool
    let cancelEnabled: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    func makeUIView(context: Context) -> RFConfirmationActionsControl { RFConfirmationActionsControl() }
    func updateUIView(_ view: RFConfirmationActionsControl, context: Context) {
        view.cancelAction = cancel
        view.cancelButton.setTitle(RFDesignStrings.text("confirmation.cancel", locale: locale), for: .normal)
        view.cancelButton.isEnabled = cancelEnabled
        view.cancelButton.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: theme.font, size: theme.size_body) ?? .preferredFont(forTextStyle: .body))
        view.cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        view.stack.spacing = theme.gap
        let button = view.confirmButton
        button.confirm = confirm; button.isEnabled = enabled
        button.accessibilityLabel = RFDesignStrings.format("confirmation.action", summary, locale: locale)
        var style = UIButton.Configuration.filled()
        style.title = RFDesignStrings.text("confirmation.confirm", locale: locale)
        style.baseForegroundColor = UIColor(theme.danger)
        style.baseBackgroundColor = UIColor(theme.danger_bg)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: theme.font, size: theme.size_body) ?? .preferredFont(forTextStyle: .body))
        style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes; result.font = font; return result
        }
        button.configuration = style
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RFConfirmationActionsControl, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }
}
#endif
