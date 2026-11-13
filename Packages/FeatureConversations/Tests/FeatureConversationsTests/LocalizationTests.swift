// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureConversations
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let key = "copy.04d7b4833927"
        let english = FeatureConversationsStrings.text(key, locale: Locale(identifier: "en"))
        let chinese = FeatureConversationsStrings.text(key, locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureConversationsStrings.text(key, locale: Locale(identifier: "en-XA"))
        #expect(english != key); #expect(chinese != key); #expect(chinese != english); #expect(expanded.count > english.count)
    }
    @Test func unreadPluralCopyUsesTheHostLocaleAndExpandsAfterFormatting() {
        let en = Locale(identifier: "en"), zh = Locale(identifier: "zh-CN"), pseudo = Locale(identifier: "en-XA")
        #expect(FeatureConversationsStrings.unread(0, locale: zh).isEmpty)
        #expect(FeatureConversationsStrings.unread(1, locale: en) == "1 unread message")
        #expect(FeatureConversationsStrings.unread(2, locale: en) == "2 unread messages")
        #expect(FeatureConversationsStrings.unread(1, locale: zh) == "1 条未读消息")
        #expect(FeatureConversationsStrings.unread(2, locale: zh) == "2 条未读消息")
        #expect(FeatureConversationsStrings.unread(2, locale: pseudo).contains("2 unread messages"))
    }
}
