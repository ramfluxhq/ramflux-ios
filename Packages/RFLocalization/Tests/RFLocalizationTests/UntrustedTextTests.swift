// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import CoreText
import Foundation
@testable import RFLocalization

@Suite(.timeLimit(.minutes(1)))
struct UntrustedTextTests {
    private static let rlo = "\u{202E}"
    private static let fsi = "\u{2068}"
    private static let lri = "\u{2066}"
    private static let pdi = "\u{2069}"

    @Test func identityTextDropsEveryDirectionalControl() {
        let raw = "Alice\u{202E}gpj.exe\u{202C}\u{2067}x\u{2069}\u{200F}"
        let clean = RFUntrustedText(raw, kind: .identity)
        #expect(clean.text == "Alicegpj.exex")
        #expect(clean.containedDirectionalControls)
        #expect(!RFUntrustedText("林悦", kind: .identity).containedDirectionalControls)
    }

    @Test func messageBodyKeepsMarksButDropsOverridesAndIsolates() {
        let raw = "\u{200F}مرحبا\u{202B} (1) \u{2066}ok\u{2069}\u{061C}"
        let clean = RFUntrustedText(raw, kind: .messageBody)
        #expect(clean.text == "\u{200F}مرحبا (1) ok\u{061C}")
        #expect(clean.containedDirectionalControls)
    }

    @Test func isolateWrapsInFirstStrongIsolateAndCannotBeClosedEarly() {
        let isolated = RFBidi.isolate("evil" + Self.pdi + Self.rlo + "txt")
        #expect(isolated == Self.fsi + "eviltxt" + Self.pdi)
        let inner = isolated.unicodeScalars.dropFirst().dropLast()
        #expect(!inner.contains { RFBidi.isEmbeddingOrIsolate($0) })
    }

    @Test func reversedExtensionCannotDisguiseAFileName() {
        // Displayed raw, U+202E would show "invoiceexe.pdf".
        let name = RFFileName("invoice" + Self.rlo + "fdp.exe")
        #expect(name.stem == "invoicefdp")
        #expect(name.fileExtension == "exe")
        #expect(name.containedDirectionalControls)
        #expect(visualOrderIsLogical(name.stem + "." + (name.fileExtension ?? "")))
    }

    @Test func fileNamesWithoutAPlainExtensionKeepTheirWholeName() {
        #expect(RFFileName(".profile").fileExtension == nil)
        #expect(RFFileName("报告").fileExtension == nil)
        #expect(RFFileName("archive.tar.gz").fileExtension == "gz")
        #expect(RFFileName("تقرير.pdf").stem == "تقرير")
        #expect(RFFileName("note.نص").fileExtension == nil)
    }

    @Test func identifierUsesWesternDigitsInsideALeftToRightIsolate() {
        #expect(RFIdentifier.display("١٢٣٤ ۵۶۷۸ ९०१२ ３４") == Self.lri + "1234 5678 9012 34" + Self.pdi)
        #expect(RFIdentifier.display("A1B2\u{202E}C3") == Self.lri + "A1B2C3" + Self.pdi)
    }

    /// Under a right-to-left paragraph the bidi algorithm puts space-separated digit groups in
    /// reversed order. The identifier display must keep the first group on the left.
    @Test(arguments: ["1111 2222 3333", "123456", "A1B2 C3D4 E5F6"])
    func identifierGroupsKeepTheirOrderUnderRightToLeft(_ identifier: String) {
        let shown = RFIdentifier.display(identifier)
        let utf16 = Array(shown.utf16)
        var offsets: [CGFloat] = []
        let line = rightToLeftLine(shown)
        for (index, unit) in utf16.enumerated() where unit != 0x20 && unit < 0x80 {
            offsets.append(CTLineGetOffsetForStringIndex(line, index, nil))
        }
        #expect(offsets == offsets.sorted(), "visual order \(offsets)")
        if identifier.contains(" "), identifier.allSatisfy({ $0.isNumber || $0 == " " }) {
            // Digit-only groups are reordered without the isolate, so the test catches a regression.
            // Letter-led groups (fingerprints) are strong left-to-right runs and keep their order anyway.
            let raw = rightToLeftLine(identifier)
            let first = CTLineGetOffsetForStringIndex(raw, 0, nil)
            let last = CTLineGetOffsetForStringIndex(raw, identifier.utf16.count - 1, nil)
            #expect(first > last, "control: raw groups reorder under a right-to-left paragraph")
        }
    }

    @Test func firstStrongDirectionSkipsMentionsLinksAndCode() {
        #expect(RFBidi.firstStrongDirection(of: "مرحبا، كيف حالك؟") == .rightToLeft)
        #expect(RFBidi.firstStrongDirection(of: "Hello مرحبا") == .leftToRight)
        #expect(RFBidi.firstStrongDirection(of: "שלום world") == .rightToLeft)
        #expect(RFBidi.firstStrongDirection(of: "收到，我会回复。") == .leftToRight)
        #expect(RFBidi.firstStrongDirection(of: "@alice مرحبا") == .rightToLeft)
        #expect(RFBidi.firstStrongDirection(of: "https://example.org/a مرحبا") == .rightToLeft)
        #expect(RFBidi.firstStrongDirection(of: "`let x` سطر") == .rightToLeft)
        #expect(RFBidi.firstStrongDirection(of: "12:30 👍 !") == nil)
    }

    @Test func sentenceIsolatesInsertedNamesWithoutConcatenation() {
        let en = Locale(identifier: "en")
        let joined = RFSentence.compose("%@ joined %@", [.untrusted("مريم"), .localized("Research")], locale: en)
        #expect(joined == Self.fsi + "مريم" + Self.pdi + " joined Research")
        let reordered = RFSentence.compose("%2$@ · %1$@", [.untrusted("A" + Self.rlo + "B"), .identifier("٤٢")], locale: en)
        #expect(reordered == Self.lri + "42" + Self.pdi + " · " + Self.fsi + "AB" + Self.pdi)
        #expect(RFSentence.compose("%lld new · 100%%", [.count(1200)], locale: en) == "1,200 new · 100%")
    }

    @Test func sentenceToleratesAMissingArgument() {
        #expect(RFSentence.compose("%@ and %@", [.untrusted("x")], locale: Locale(identifier: "en")) == Self.fsi + "x" + Self.pdi + " and ")
        #expect(RFSentence.compose("50% done", [], locale: Locale(identifier: "en")) == "50% done")
    }

    private func rightToLeftLine(_ text: String) -> CTLine {
        var direction = CTWritingDirection.rightToLeft
        let paragraph = withUnsafeBytes(of: &direction) { bytes in
            var setting = CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size, value: bytes.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 17, nil),
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ])
        return CTLineCreateWithAttributedString(attributed)
    }

    /// True when every glyph run of the text is left to right and runs follow string order.
    private func visualOrderIsLogical(_ text: String) -> Bool {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text))
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return false }
        var last = -1
        for run in runs {
            if CTRunGetStatus(run).contains(.rightToLeft) { return false }
            let start = CTRunGetStringRange(run).location
            if start < last { return false }
            last = start
        }
        return true
    }
}
