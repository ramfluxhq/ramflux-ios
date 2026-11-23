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
    /// Receipts are structured data, never pre-formatted text; only known states are kept.
    @Test func receiptsAreStructuredWithoutPreformattedText() {
        let rows: JSONValue = .array([
            .object(["device_id": .string("phone-1"), "state": .string("read")]),
            .object(["device_id": .string("phone-2"), "state": .string("delivered")]),
            .object(["device_id": .string("ignored"), "state": .string("typing")]),
        ])
        #expect(MessagePage.receiptRows(rows) == [MessageReceipt(device: "phone-1", state: .read), MessageReceipt(device: "phone-2", state: .delivered)])
        #expect(MessagePage.receiptRows(.string("read")).isEmpty)
    }
}
