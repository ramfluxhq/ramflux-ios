// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RFLocalization
public enum FeatureCallsStrings {
    public static func text(_ key: String, locale: Locale = .current) -> String {
        CatalogLookup.text(key, bundle: .module, locale: locale)
    }
    public static func duration(_ seconds: Int64, locale: Locale) -> String {
        let resolved = CatalogLookup.resolve("calls.duration %lld", in: .module, locale: locale)
        return String(localized: "calls.duration \(seconds)", bundle: resolved.bundle, locale: resolved.locale)
    }
    public static func format(_ key: String, _ arguments: CVarArg..., locale: Locale = .current) -> String {
        CatalogLookup.format(key, arguments, bundle: .module, locale: locale)
    }
    public static func sentence(_ key: String, _ arguments: [RFTextArgument], locale: Locale = .current) -> String {
        CatalogLookup.sentence(key, arguments, bundle: .module, locale: locale)
    }
}
