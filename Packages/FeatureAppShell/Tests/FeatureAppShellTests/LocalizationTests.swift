// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureAppShell
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.446531641e6a"
        let english = FeatureAppShellStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = FeatureAppShellStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureAppShellStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
