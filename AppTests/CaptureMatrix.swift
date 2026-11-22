// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

/// The single parameter list for every capture test. Adding a locale, width,
/// text size or theme here extends board captures and feature snapshots alike;
/// no test is duplicated per locale.
enum CaptureMatrix {
    struct CaptureLocale {
        /// Locale identifier used in file names and passed to the views.
        var id: String
        var layoutDirection: LayoutDirection
        var locale: Locale { Locale(identifier: id) }
    }

    struct Canvas {
        var width: Int
        var height: Int
        var size: CGSize { CGSize(width: width, height: height) }
    }

    struct TextSize {
        var name: String
        var size: DynamicTypeSize
    }

    struct Theme {
        var name: String
        var scheme: ColorScheme
    }

    /// `en-XA` is the expanded pseudo-locale. `ar` has no catalog: every
    /// lookup falls back to English, and the layout runs right to left over the
    /// Arabic sample fixtures.
    static let locales = [
        CaptureLocale(id: "en", layoutDirection: .leftToRight),
        CaptureLocale(id: "zh-CN", layoutDirection: .leftToRight),
        CaptureLocale(id: "en-XA", layoutDirection: .leftToRight),
        CaptureLocale(id: "ar", layoutDirection: .rightToLeft),
    ]

    /// Narrow phone or Slide Over, the design board, and an iPad mini portrait window.
    static let canvases = [
        Canvas(width: 320, height: 568),
        Canvas(width: 393, height: 852),
        Canvas(width: 744, height: 1133),
    ]

    static let textSizes = [
        TextSize(name: "default", size: .large),
        TextSize(name: "ax3", size: .accessibility3),
    ]

    static let themes = [
        Theme(name: "light", scheme: .light),
        Theme(name: "dark", scheme: .dark),
    ]

    /// Only this canvas at the default text size is compared with design boards.
    static let board = Canvas(width: 393, height: 852)

    static func captureName(board: String, locale: CaptureLocale, canvas: Canvas, textSize: TextSize, theme: Theme) -> String {
        "\(board)-\(locale.id)-\(canvas.width)-\(textSize.name)-\(theme.name)"
    }
}
