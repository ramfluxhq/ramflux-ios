// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureGroups
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let english = FeatureGroupsStrings.text("groups.title", locale: Locale(identifier: "en"))
        let chinese = FeatureGroupsStrings.text("groups.title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureGroupsStrings.text("groups.title", locale: Locale(identifier: "en-XA"))
        #expect(english != "groups.title"); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
