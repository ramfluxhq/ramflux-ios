// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureCalls
struct LocalizationTests {
    @Test func englishChineseExpandedAndPluralCopyResolve() {
        let english = FeatureCallsStrings.text("calls.title", locale: Locale(identifier: "en"))
        let chinese = FeatureCallsStrings.text("calls.title", locale: Locale(identifier: "zh-CN"))
        #expect(english != "calls.title"); #expect(chinese != english)
        #expect(FeatureCallsStrings.text("calls.title", locale: Locale(identifier: "en-XA")).count > english.count)
        #expect(FeatureCallsStrings.duration(1, locale: Locale(identifier: "en")) == "1 second")
        #expect(FeatureCallsStrings.duration(2, locale: Locale(identifier: "en")) == "2 seconds")
        #expect(FeatureCallsStrings.duration(2, locale: Locale(identifier: "zh-CN")) == "2 秒")
    }
    @Test func unavailableReasonResolvesAtPresentationInChineseAndExpandedLocale() {
        let reason = UnavailableCallsRepository().audioUnavailable()
        let en = reason.message(locale: Locale(identifier: "en")), zh = reason.message(locale: Locale(identifier: "zh-CN")), pseudo = reason.message(locale: Locale(identifier: "en-XA"))
        #expect(en != zh); #expect(pseudo.count > en.count); #expect(!en.contains("unavailableResource"))
    }
}
