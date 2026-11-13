// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureAgents
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let english = FeatureAgentsStrings.text("agents.title", locale: Locale(identifier: "en"))
        let chinese = FeatureAgentsStrings.text("agents.title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureAgentsStrings.text("agents.title", locale: Locale(identifier: "en-XA"))
        #expect(english != "agents.title"); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}
