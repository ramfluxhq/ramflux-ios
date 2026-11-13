// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureTasks
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let english = FeatureTasksStrings.text("tasks.title", locale: Locale(identifier: "en"))
        let chinese = FeatureTasksStrings.text("tasks.title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureTasksStrings.text("tasks.title", locale: Locale(identifier: "en-XA"))
        #expect(english != "tasks.title"); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
