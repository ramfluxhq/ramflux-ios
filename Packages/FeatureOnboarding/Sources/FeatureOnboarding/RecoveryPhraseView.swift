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
    public func updateUIView(_ view: RecoveryGlyphView, context: Context) { view.display = display; view.ink = UIColor(theme.text); view.setNeedsDisplay() }
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: RecoveryGlyphView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize
        let columns = width >= size * 20 ? 2 : 1
        return CGSize(width: width, height: CGFloat(24 / columns) * size * 1.6 + size)
    }
    public static func dismantleUIView(_ view: RecoveryGlyphView, coordinator: ()) { view.display = nil; view.setNeedsDisplay() }
}
#endif
