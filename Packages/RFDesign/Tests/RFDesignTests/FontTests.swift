// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import CoreText
@testable import RFDesign
struct FontTests {
    @Test func packagedFacesResolveToTheirOwnPostScriptNamesAndFiles() {
        #expect(DesignFonts.registered)
        for face in DesignFonts.expectedFaces { #expect(CTFontCopyPostScriptName(CTFontCreateWithName(face as CFString, 17, nil)) as String == face) }
        #expect(RFTheme.light.font == DesignFonts.expectedFaces[0])
    }
}
