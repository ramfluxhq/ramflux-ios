// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import CoreText
import AppData
import RFDesign

public struct RecoveryPhraseView: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let display: RecoveryDisplay
    public func makeUIView(context: Context) -> RecoveryGlyphView { RecoveryGlyphView(display: display) }
    public func updateUIView(_ view: RecoveryGlyphView, context: Context) { view.present(display: display, label: FeatureOnboardingStrings.text("copy.043a01d16971", locale: locale), ink: UIColor(theme.text), fontName: DesignFonts.face(for: theme.font_mono), pointSize: UIFontMetrics(forTextStyle: .body).scaledValue(for: theme.size_mobile_body)) }
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: RecoveryGlyphView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = UIFontMetrics(forTextStyle: .body).scaledValue(for: theme.size_mobile_body)
        let columns = width >= size * 20 ? 2 : 1
        return CGSize(width: width, height: CGFloat(24 / columns) * size * 1.6 + size)
    }
    public static func dismantleUIView(_ view: RecoveryGlyphView, coordinator: ()) { view.display = nil; view.setNeedsDisplay() }
}
#endif
