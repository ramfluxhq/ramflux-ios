// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RFLocalization
public enum FeatureSettingsStrings {
    public static func text(_ key: String, locale: Locale = .current) -> String {
        CatalogLookup.text(key, bundle: .module, locale: locale)
    }
    public static func format(_ key: String, _ arguments: CVarArg..., locale: Locale = .current) -> String {
        CatalogLookup.format(key, arguments, bundle: .module, locale: locale)
    }
}
