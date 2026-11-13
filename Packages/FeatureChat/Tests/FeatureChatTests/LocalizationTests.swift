// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureChat
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.01fad993ff61"
        let english = FeatureChatStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = FeatureChatStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureChatStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
