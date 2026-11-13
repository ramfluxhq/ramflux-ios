// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureContacts
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.0013e6984bf6"
        let english = FeatureContactsStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = FeatureContactsStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureContactsStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
