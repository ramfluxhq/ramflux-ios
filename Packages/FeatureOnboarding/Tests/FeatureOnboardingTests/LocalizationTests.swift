// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureOnboarding
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.0234cae2e221"
        let english = FeatureOnboardingStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = FeatureOnboardingStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureOnboardingStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
