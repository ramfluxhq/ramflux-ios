// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import CoreText
@testable import RFDesign
@Suite(.timeLimit(.minutes(2)))
struct FontTests {
    @Test func packagedFacesResolveToTheirOwnPostScriptNamesAndFiles() {
        #expect(DesignFonts.registered)
        for face in DesignFonts.expectedFaces { #expect(CTFontCopyPostScriptName(CTFontCreateWithName(face as CFString, 17, nil)) as String == face) }
        #expect(RFTheme.light.font == DesignFonts.expectedFaces[0])
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
