// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import Push
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromCatalog() {
        let en = PushStrings.text("push.message.body", locale: Locale(identifier: "en"))
        let zh = PushStrings.text("push.message.body", locale: Locale(identifier: "zh-CN"))
        let expanded = PushStrings.text("push.message.body", locale: Locale(identifier: "en-XA"))
        #expect(en == "New message"); #expect(zh == "新消息"); #expect(expanded.count > en.count)
    }
}
