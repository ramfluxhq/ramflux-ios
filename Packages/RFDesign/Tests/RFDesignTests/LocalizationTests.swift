// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import RFDesign
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.a2538eaa411f"
        let english = RFDesignStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = RFDesignStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = RFDesignStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
