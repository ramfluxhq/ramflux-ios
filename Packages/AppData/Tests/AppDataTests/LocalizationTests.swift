// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import Testing
@testable import AppData
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "common.tab.messages"
        let english = AppDataStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = AppDataStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = AppDataStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
    @Test func localeWithoutTranslationsShowsEnglishNotTheKey() {
        let key = "common.tab.messages"
        let english = AppDataStrings.text(key, locale: Locale(identifier: "en"))
        #expect(AppDataStrings.text(key, locale: Locale(identifier: "ar")) == english)
        #expect(AppDataStrings.text(key, locale: Locale(identifier: "de-DE")) == english)
        #expect(AppDataStrings.status("delivered", locale: Locale(identifier: "ar")) == AppDataStrings.status("delivered", locale: Locale(identifier: "en")))
    }
    @Test func receiptsKeepDeviceIdsLeftToRightWithoutALiteralSeparator() throws {
        let rows: JSONValue = .array([
            .object(["device_id": .string("٤٢\u{202E}a"), "state": .string("read")]),
            .object(["device_id": .string("phone-2"), "state": .string("delivered")]),
            .object(["device_id": .string("ignored"), "state": .string("typing")]),
        ])
        let text = try #require(MessagePage.receiptText(rows, own: true))
        #expect(text.contains("\u{2066}42a\u{2069}"))
        #expect(text.contains("\u{2066}phone-2\u{2069}"))
        #expect(!text.contains("\u{202E}"))
        #expect(!text.contains("ignored"))
        #expect(MessagePage.receiptText(rows, own: false) == nil)
    }
}
