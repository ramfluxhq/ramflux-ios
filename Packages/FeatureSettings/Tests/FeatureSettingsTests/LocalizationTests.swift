// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureSettings
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.01a234cb80c4"
        let english = FeatureSettingsStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = FeatureSettingsStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureSettingsStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
    @Test func expandedVariablesAreFormattedBeforeExpansion() {
        let english = FeatureSettingsStrings.format("backup.jobSummary", "restore", "verified", locale: Locale(identifier: "en"))
        let expanded = FeatureSettingsStrings.format("backup.jobSummary", "restore", "verified", locale: Locale(identifier: "en-XA"))
        #expect(expanded == "［" + english + " · " + english + "］")
    }
}
