// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CoreText
/// Registration happens once, before token adapters hand faces to any native renderer.
public enum DesignFonts {
    public static let expectedFaces = ["NotoSansSC-Thin_Regular", "HankenGrotesk-Regular", "JetBrainsMono-Regular"]
    private static let files = ["NotoSansSC", "HankenGrotesk", "JetBrainsMono"]
    public static let registered: Bool = {
        var valid = true
        for (file, face) in zip(files, expectedFaces) {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else { valid = false; continue }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let font = CTFontCreateWithName(face as CFString, 17, nil)
            valid = valid && CTFontCopyPostScriptName(font) as String == face
            if let actual = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL { valid = valid && actual.standardizedFileURL == url.standardizedFileURL } else { valid = false }
        }
        return valid
    }()
    public static func face(for token: String) -> String {
        _ = registered
        return switch token { case "Noto Sans SC": expectedFaces[0]; case "Hanken Grotesk": expectedFaces[1]; case "JetBrains Mono": expectedFaces[2]; default: token }
    }
}
