// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import CoreText
import Foundation
@testable import RFDesign
@Suite(.timeLimit(.minutes(2)))
struct FontTests {
    @Test func packagedFacesResolveToTheirOwnPostScriptNamesAndFiles() {
        #expect(DesignFonts.registered)
        for face in DesignFonts.expectedFaces { #expect(CTFontCopyPostScriptName(CTFontCreateWithName(face as CFString, 17, nil)) as String == face) }
        #expect(RFTheme.light.font == DesignFonts.expectedFaces[0])
    }

    /// The bundled faces draw Latin and Simplified Chinese as the design specifies; text they
    /// cannot draw, and ideographs under locales with their own Han forms, use the system font.
    @Test(arguments: [
        ("Messages", "en", KitFontRole.ui, "NotoSansSC-Thin_Regular"),
        ("消息", "zh-CN", .ui, "NotoSansSC-Thin_Regular"),
        ("林悦 👍", "en", .ui, "NotoSansSC-Thin_Regular"),
        ("10:24", "en", .latin, "HankenGrotesk-Regular"),
        ("Agents", "zh-CN", .latin, "HankenGrotesk-Regular"),
        ("智能体", "zh-CN", .latin, "NotoSansSC-Thin_Regular"),
        ("4821 7730", "ar", .mono, "JetBrainsMono-Regular"),
        ("الرسائل", "ar", .ui, "system"),
        ("الوكلاء", "ar", .latin, "system"),
        ("١٠:٢٤", "ar", .latin, "system"),
        ("메시지", "ko", .ui, "system"),
        ("संदेश", "hi", .ui, "system"),
        ("メッセージ", "ja", .ui, "system"),
        ("訊息", "zh-Hant", .ui, "system"),
        ("消息", "ja", .ui, "system"),
        ("שלום", "en", .mono, "systemMono"),
        ("Сообщения", "ru", .ui, "system"),
        ("Mesajlar", "tr", .ui, "HankenGrotesk-Regular"),
        ("Güvenlik ayarları", "tr", .ui, "HankenGrotesk-Regular"),
        ("Tiếng Việt", "en", .ui, "HankenGrotesk-Regular"),
        ("Größe", "de", .ui, "NotoSansSC-Thin_Regular"),
    ])
    func faceFollowsScriptAndLocale(_ text: String, _ locale: String, _ role: KitFontRole, _ expected: String) {
        let face = KitTypeface.face(for: role, text: text, locale: Locale(identifier: locale))
        let name = switch face {
        case .bundled(let postScript): postScript
        case .system: "system"
        case .systemMono: "systemMono"
        }
        #expect(name == expected, "\(text) in \(locale)")
    }

    @Test func editableTextUsesTheBundledFaceOnlyForLatinAndSimplifiedChinese() {
        #expect(KitTypeface.face(for: .ui, locale: Locale(identifier: "en")).isBundled)
        #expect(KitTypeface.face(for: .ui, locale: Locale(identifier: "zh-CN")).isBundled)
        #expect(KitTypeface.face(for: .ui, locale: Locale(identifier: "de")) == .bundled("NotoSansSC-Thin_Regular"))
        #expect(KitTypeface.face(for: .ui, locale: Locale(identifier: "tr")) == .bundled("HankenGrotesk-Regular"))
        for identifier in ["ar", "ja", "ko", "zh-TW", "zh-Hant", "hi", "ru"] {
            #expect(!KitTypeface.face(for: .ui, locale: Locale(identifier: identifier)).isBundled, "\(identifier)")
        }
    }

    /// System faces keep at least their own ascent plus descent; the design line height only adds space.
    @Test func systemFaceLinesAreNeverShorterThanTheFace() {
        let font = kitCTFont(size: 17, weight: 400, face: .system)
        let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        #expect(kitLineSpacing(size: 17, weight: .regular, line: 1.0, face: .system) == 0)
        #expect(abs(kitLineSpacing(size: 17, weight: .regular, line: 2.0, face: .system) - (34 - natural)) < 0.01)
    }

    @Test func textScalesWithDynamicType() {
        #expect(kitScaledSize(17, .large) == 17)
        #expect(kitScaledSize(17, .accessibility3) > 30)
        #expect(kitScaledSize(17, .xSmall) < 17)
    }

    @Test func trackingOnlyAppliesToAsciiRuns() {
        #expect(kitTrackingAllowed("PDF"))
        #expect(kitTrackingAllowed(RFIdentifier.display("4821 7730")))
        #expect(!kitTrackingAllowed("ملف"))
        #expect(!kitTrackingAllowed("文件"))
    }

    @Test func bundledFontLicensesLoadInFull() {
        let licenses = DesignFontLicenses.load()
        #expect(licenses.map(\.name) == ["Hanken Grotesk", "JetBrains Mono", "Noto Sans SC"])
        for license in licenses {
            #expect(license.text.contains("SIL Open Font License"))
            #expect(license.text.count > 200)
        }
    }
}
