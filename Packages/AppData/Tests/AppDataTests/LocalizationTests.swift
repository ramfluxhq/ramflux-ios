// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import AppData
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.04d7b4833927"
        let english = AppDataStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = AppDataStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = AppDataStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
