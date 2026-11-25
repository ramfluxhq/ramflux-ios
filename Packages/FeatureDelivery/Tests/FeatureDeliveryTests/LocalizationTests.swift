// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureDelivery
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromCatalog() {
        let en = FeatureDeliveryStrings.text("title", locale: Locale(identifier: "en"))
        let zh = FeatureDeliveryStrings.text("title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureDeliveryStrings.text("title", locale: Locale(identifier: "en-XA"))
        #expect(en == "Message delivery"); #expect(zh == "消息送达"); #expect(expanded.count > en.count)
    }
}
