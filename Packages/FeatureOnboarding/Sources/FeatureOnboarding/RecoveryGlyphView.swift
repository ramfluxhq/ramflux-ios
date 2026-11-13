// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import CoreText
import AppData
import RFDesign

@MainActor public final class RecoveryGlyphView: UIView {
    var ink = UIColor(RFTheme.light.text)
    var display: RecoveryDisplay?
    private(set) var pointSize: CGFloat = 17
    private(set) var fontName = ""
    func present(display: RecoveryDisplay, label: String, ink: UIColor, fontName: String, pointSize: CGFloat) {
        self.display = display; accessibilityLabel = label; self.ink = ink; self.fontName = fontName; self.pointSize = pointSize
        invalidateIntrinsicContentSize(); setNeedsDisplay()
    }
    init(display: RecoveryDisplay) {
        self.display = display; super.init(frame: .zero); backgroundColor = .clear
        isAccessibilityElement = true
    }
    public required init?(coder: NSCoder) { return nil }
    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        let size = pointSize
        let columns = bounds.width >= size * 20 ? 2 : 1
        let rows = 24 / columns
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font) + size * 0.6
        context.setFillColor(ink.cgColor)
        display?.withDrawingBytes { raw in
            var advanceX: CGFloat = 0, word = 0
            for byte in raw {
                if byte == 32 { word += 1; advanceX = 0; continue }
                var character = UniChar(byte), glyph = CGGlyph(0)
                _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
                var point = CGPoint(x: CGFloat(word / rows) * bounds.width / CGFloat(columns) + advanceX, y: bounds.height - size - CGFloat(word % rows) * lineHeight)
                CTFontDrawGlyphs(font, &glyph, &point, 1, context)
                var advance = CGSize.zero; _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1); advanceX += advance.width
            }
        }
    }
}
#endif
