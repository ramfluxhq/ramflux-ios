// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import CoreText
import AppData
import RFDesign

@MainActor public final class RecoveryGlyphView: UIView {
    var ink = UIColor(RFDesign.light.text)
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
        let font = CTFontCreateWithName(RFDesign.light.font_mono as CFString, size, nil)
        context.setFillColor(ink.cgColor)
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
