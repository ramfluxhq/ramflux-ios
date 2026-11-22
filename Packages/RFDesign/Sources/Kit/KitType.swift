// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The typeface a component asks for. The face that draws the text is chosen by `KitTypeface`
/// from the text's script and the active locale, never from the caller.
enum KitFontRole: Sendable { case ui, latin, mono }

/// The face that actually draws a run of text.
enum KitFace: Equatable, Sendable {
    /// A bundled design face, by PostScript name.
    case bundled(String)
    /// The platform UI font. It carries its own metrics for scripts the bundled faces do not cover.
    case system
    /// The platform monospaced font.
    case systemMono

    var isBundled: Bool { if case .bundled = self { true } else { false } }
}

/// Chooses a face per text and locale.
///
/// - Latin and Simplified Chinese use the bundled faces the design specifies.
/// - Text with any letter a bundled face cannot draw (Arabic, Hangul, Devanagari, Cyrillic,
///   ideographs outside the subset, ...) uses the system font with its own line metrics.
/// - Ideographs under a locale whose script has its own Han glyph forms (Traditional Chinese,
///   Japanese, Korean) use the system font, which picks the locale's forms.
enum KitTypeface {
    private static let ownHanForms: Set<String> = ["Hant", "Jpan", "Kore"]
    private static let bundledScripts: Set<String> = ["Latn", "Hans"]

    static func face(for role: KitFontRole, text: String, locale: Locale) -> KitFace {
        let preferred = bundledFace(role)
        let script = localeScript(locale)
        var hasIdeograph = false
        var coveredByPreferred = true
        var coveredByUI = true
        for scalar in text.unicodeScalars where counts(scalar) {
            if scalar.properties.isIdeographic { hasIdeograph = true }
            if coveredByPreferred && !covers(preferred, scalar) { coveredByPreferred = false }
            if role == .latin && coveredByUI && !covers(bundledFace(.ui), scalar) { coveredByUI = false }
        }
        if hasIdeograph, let script, ownHanForms.contains(script) { return systemFace(role) }
        if coveredByPreferred { return .bundled(preferred) }
        if role == .latin && coveredByUI { return .bundled(bundledFace(.ui)) }
        return systemFace(role)
    }

    /// The face for editable text, where the content is not known in advance.
    static func face(for role: KitFontRole, locale: Locale) -> KitFace {
        guard let script = localeScript(locale), bundledScripts.contains(script) else { return systemFace(role) }
        return .bundled(bundledFace(role))
    }

    static func localeScript(_ locale: Locale) -> String? {
        let maximal = Locale.Language(identifier: locale.language.maximalIdentifier)
        return maximal.script?.identifier
    }

    static func bundledFace(_ role: KitFontRole) -> String {
        switch role {
        case .ui: DesignFonts.face(for: "Noto Sans SC")
        case .latin: DesignFonts.face(for: "Hanken Grotesk")
        case .mono: DesignFonts.face(for: "JetBrains Mono")
        }
    }

    private static func systemFace(_ role: KitFontRole) -> KitFace { role == .mono ? .systemMono : .system }

    /// Whitespace, controls, format characters, variation selectors and emoji do not decide the face;
    /// the system cascade draws them in any face.
    private static func counts(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        if properties.isWhitespace || properties.isEmojiPresentation { return false }
        switch properties.generalCategory {
        case .control, .format, .otherSymbol, .privateUse, .surrogate, .unassigned: return false
        default: break
        }
        return !(0xFE00...0xFE0F).contains(scalar.value) && !(0xE0100...0xE01EF).contains(scalar.value)
    }

    private static func covers(_ face: String, _ scalar: Unicode.Scalar) -> Bool {
        guard let set = KitCoverage.sets[face] else { return false }
        return CFCharacterSetIsLongCharacterMember(set, UTF32Char(scalar.value))
    }
}

private enum KitCoverage {
    /// Character sets are immutable once created; reads from several threads are safe.
    nonisolated(unsafe) static let sets: [String: CFCharacterSet] = {
        _ = DesignFonts.registered
        var sets: [String: CFCharacterSet] = [:]
        for face in DesignFonts.expectedFaces {
            sets[face] = CTFontCopyCharacterSet(CTFontCreateWithName(face as CFString, 17, nil))
        }
        return sets
    }()
}

func kitCTFont(size: CGFloat, weight: CGFloat, face: KitFace) -> CTFont {
    switch face {
    case .bundled(let name):
        _ = DesignFonts.registered
        let axis = NSNumber(value: 0x77676874)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name as CFString,
            kCTFontVariationAttribute: [axis: NSNumber(value: Double(weight))]
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    case .system:
        #if canImport(UIKit)
        return UIFont.systemFont(ofSize: size, weight: kitPlatformWeight(weight)) as CTFont
        #else
        return NSFont.systemFont(ofSize: size, weight: kitPlatformWeight(weight)) as CTFont
        #endif
    case .systemMono:
        #if canImport(UIKit)
        return UIFont.monospacedSystemFont(ofSize: size, weight: kitPlatformWeight(weight)) as CTFont
        #else
        return NSFont.monospacedSystemFont(ofSize: size, weight: kitPlatformWeight(weight)) as CTFont
        #endif
    }
}

/// The bundled face of a role, for metrics that the design states in that face.
func kitCTFont(size: CGFloat, weight: CGFloat, role: KitFontRole) -> CTFont {
    kitCTFont(size: size, weight: weight, face: .bundled(KitTypeface.bundledFace(role)))
}

func kitFont(size: CGFloat, weight: CGFloat, face: KitFace) -> Font {
    switch face {
    case .bundled:
        let varied = kitCTFont(size: size, weight: weight, face: face)
        #if canImport(UIKit)
        return Font(UIFont(descriptor: CTFontCopyFontDescriptor(varied) as UIFontDescriptor, size: size))
        #else
        let descriptor = CTFontCopyFontDescriptor(varied) as NSFontDescriptor
        if let font = NSFont(descriptor: descriptor, size: size) { return Font(font) }
        let named = NSFont(name: CTFontCopyPostScriptName(varied) as String, size: size)
        return Font(named ?? NSFont.systemFont(ofSize: size))
        #endif
    case .system:
        return .system(size: size, weight: kitSwiftUIWeight(weight))
    case .systemMono:
        return .system(size: size, weight: kitSwiftUIWeight(weight), design: .monospaced)
    }
}

/// Design line height for a face.
///
/// Bundled faces (Latin, Simplified Chinese) take the exact design line height where the platform
/// supports it, as the design specifies. Every other face keeps at least its own ascent plus descent:
/// spacing is only ever added, so tall marks of fallback scripts (Arabic tashkeel, Devanagari) are
/// never squeezed or clipped.
struct KitLineHeight: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight
    var line: CGFloat
    var face: KitFace

    func body(content: Content) -> some View {
        if face.isBundled, #available(iOS 26.0, macOS 26.0, *) {
            content.lineHeight(.exact(points: size * line))
        } else {
            content.lineSpacing(kitLineSpacing(size: size, weight: weight, line: line, face: face))
        }
    }
}

/// Extra space between lines so a line reaches the design line height. It never shrinks a line
/// below the face's own ascent plus descent.
func kitLineSpacing(size: CGFloat, weight: Font.Weight, line: CGFloat, face: KitFace) -> CGFloat {
    let font = kitCTFont(size: size, weight: kitWeight(weight), face: face)
    let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    return max(0, size * line - natural)
}

func kitWeight(_ weight: Font.Weight) -> CGFloat {
    switch weight {
    case .bold: 700
    case .semibold: 600
    case .medium: 500
    default: 400
    }
}

private func kitSwiftUIWeight(_ weight: CGFloat) -> Font.Weight {
    switch weight {
    case 650...: .bold
    case 550..<650: .semibold
    case 450..<550: .medium
    default: .regular
    }
}

#if canImport(UIKit)
private func kitPlatformWeight(_ weight: CGFloat) -> UIFont.Weight {
    switch weight {
    case 650...: .bold
    case 550..<650: .semibold
    case 450..<550: .medium
    default: .regular
    }
}
#else
private func kitPlatformWeight(_ weight: CGFloat) -> NSFont.Weight {
    switch weight {
    case 650...: .bold
    case 550..<650: .semibold
    case 450..<550: .medium
    default: .regular
    }
}
#endif

/// The design size scaled for the reader's text size. Design sizes are the `large` (default) size.
/// iOS uses the system's scaling curve for the text style closest to the design size.
func kitScaledSize(_ size: CGFloat, _ typeSize: DynamicTypeSize) -> CGFloat {
    #if canImport(UIKit)
    let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
    return UIFontMetrics(forTextStyle: kitTextStyle(size)).scaledValue(for: size, compatibleWith: traits)
    #else
    return size * kitBodyScale(typeSize)
    #endif
}

#if canImport(UIKit)
func kitTextStyle(_ size: CGFloat) -> UIFont.TextStyle {
    switch size {
    case 34...: .largeTitle
    case 28..<34: .title1
    case 22..<28: .title2
    case 20..<22: .title3
    case 17..<20: .body
    case 16..<17: .callout
    case 15..<16: .subheadline
    case 13..<15: .footnote
    case 12..<13: .caption1
    default: .caption2
    }
}
#endif

/// The body text style's sizes per text size, relative to `large`. macOS hosts have no Dynamic Type;
/// unit tests use this table to exercise the same layouts.
func kitBodyScale(_ typeSize: DynamicTypeSize) -> CGFloat {
    let points: CGFloat = switch typeSize {
    case .xSmall: 14
    case .small: 15
    case .medium: 16
    case .large: 17
    case .xLarge: 19
    case .xxLarge: 21
    case .xxxLarge: 23
    case .accessibility1: 28
    case .accessibility2: 33
    case .accessibility3: 40
    case .accessibility4: 47
    case .accessibility5: 53
    @unknown default: 17
    }
    return points / 17
}

/// Letter-spacing breaks the joining of cursive scripts. It applies only to ASCII text (Latin identifiers).
func kitTrackingAllowed(_ text: String) -> Bool { text.unicodeScalars.allSatisfy(\.isASCII) }

/// A single run of Kit text at a design size. The size follows Dynamic Type, the face follows the
/// text's script, and lines grow to the face's natural height.
struct KitLabel: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight
    var color: Color
    var line: CGFloat
    var role: KitFontRole
    var tracking: CGFloat
    var lines: Int?
    /// Glyphs inside a fixed shape (avatar initials, reaction emoji, the simulated status bar) keep the design size.
    var scales: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    init(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        color: Color,
        line: CGFloat = KitMetrics.lineBody,
        role: KitFontRole = .ui,
        tracking: CGFloat = 0,
        lines: Int? = 1,
        scales: Bool = true
    ) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
        self.line = line
        self.role = role
        self.tracking = tracking
        self.lines = lines
        self.scales = scales
    }

    var body: some View {
        let scaled = scales ? kitScaledSize(size, typeSize) : size
        let face = KitTypeface.face(for: role, text: text, locale: locale)
        Text(text)
            .font(kitFont(size: scaled, weight: kitWeight(weight), face: face))
            .foregroundStyle(color)
            .modifier(KitLineHeight(size: scaled, weight: weight, line: line, face: face))
            .tracking(kitTrackingAllowed(text) ? tracking : 0)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: lines == nil)
    }
}

/// Font for editable Kit text, scaled for Dynamic Type and chosen from the locale's script.
struct KitFieldFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight = .regular
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    func body(content: Content) -> some View {
        content.font(kitFont(size: kitScaledSize(size, typeSize), weight: kitWeight(weight), face: KitTypeface.face(for: .ui, locale: locale)))
    }
}
