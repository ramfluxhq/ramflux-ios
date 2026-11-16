// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import CoreText
import SwiftUI

enum KitFontRole { case ui, latin, mono }

func kitCTFont(size: CGFloat, weight: CGFloat, role: KitFontRole) -> CTFont {
    let token = switch role {
    case .ui: "Noto Sans SC"
    case .latin: "Hanken Grotesk"
    case .mono: "JetBrains Mono"
    }
    _ = DesignFonts.registered
    let name = DesignFonts.face(for: token) as CFString
    let axis = NSNumber(value: 0x77676874)
    let descriptor = CTFontDescriptorCreateWithAttributes([
        kCTFontNameAttribute: name,
        kCTFontVariationAttribute: [axis: NSNumber(value: Double(weight))]
    ] as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

func kitFont(size: CGFloat, weight: CGFloat, role: KitFontRole) -> Font {
    let varied = kitCTFont(size: size, weight: weight, role: role)
    #if canImport(UIKit)
    return Font(UIFont(descriptor: CTFontCopyFontDescriptor(varied) as UIFontDescriptor, size: size))
    #else
    let descriptor = CTFontCopyFontDescriptor(varied) as NSFontDescriptor
    if let font = NSFont(descriptor: descriptor, size: size) { return Font(font) }
    let named = NSFont(name: CTFontCopyPostScriptName(varied) as String, size: size)
    return Font(named ?? NSFont.systemFont(ofSize: size))
    #endif
}

func kitLineSpacing(size: CGFloat, weight: Font.Weight, line: CGFloat, role: KitFontRole) -> CGFloat {
    let font = kitCTFont(size: size, weight: kitWeight(weight), role: role)
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
