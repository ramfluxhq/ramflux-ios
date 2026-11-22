// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RFLocalization
public enum FeatureConversationsStrings {
    public static func text(_ key: String, locale: Locale = .current) -> String {
        CatalogLookup.text(key, bundle: .module, locale: locale)
    }
    public static func unread(_ count: UInt, locale: Locale) -> String {
        guard count > 0 else { return "" }
        let expanded = CatalogLookup.isExpanded(locale)
        let resolved = CatalogLookup.resolve("conversations.unread %llu", in: .module, locale: expanded ? Locale(identifier: CatalogLookup.developmentLanguage) : locale)
        let value = String(localized: "conversations.unread \(count)", bundle: resolved.bundle, locale: resolved.locale)
        return expanded ? CatalogLookup.expand(value) : value
    }
    public static func format(_ key: String, _ arguments: CVarArg..., locale: Locale = .current) -> String {
        CatalogLookup.format(key, arguments, bundle: .module, locale: locale)
    }
    public static func sentence(_ key: String, _ arguments: [RFTextArgument], locale: Locale = .current) -> String {
        CatalogLookup.sentence(key, arguments, bundle: .module, locale: locale)
    }
}
