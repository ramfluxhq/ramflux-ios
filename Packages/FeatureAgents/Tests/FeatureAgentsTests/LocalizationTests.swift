// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureAgents
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let english = FeatureAgentsStrings.text("agents.title", locale: Locale(identifier: "en"))
        let chinese = FeatureAgentsStrings.text("agents.title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureAgentsStrings.text("agents.title", locale: Locale(identifier: "en-XA"))
        #expect(english != "agents.title"); #expect(chinese != english); #expect(expanded.count > english.count)
    }
    @Test func unavailableReasonResolvesAtPresentationInChineseAndExpandedLocale() {
        let reason = AppFailure.unavailableResource("agents.unavailable")
        let en = reason.message(locale: Locale(identifier: "en")), zh = reason.message(locale: Locale(identifier: "zh-CN")), pseudo = reason.message(locale: Locale(identifier: "en-XA"))
        #expect(en != zh); #expect(pseudo.count > en.count); #expect(!en.contains("unavailableResource"))
    }
}
