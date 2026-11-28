// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureMlsGroups
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let english = FeatureMlsGroupsStrings.text("group.list.title", locale: Locale(identifier: "en"))
        let chinese = FeatureMlsGroupsStrings.text("group.list.title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureMlsGroupsStrings.text("group.list.title", locale: Locale(identifier: "en-XA"))
        #expect(english != "group.list.title"); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
