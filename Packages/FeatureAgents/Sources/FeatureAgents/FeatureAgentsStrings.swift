// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum FeatureAgentsStrings {
    public static func text(_ key: String, locale: Locale = .current) -> String {
        let source: Bundle = .module
        let language = Bundle.preferredLocalizations(from: source.localizations, forPreferences: [locale.identifier.replacingOccurrences(of: "_", with: "-")]).first ?? "en"
        let localized = source.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? source
        let value = String(localized: String.LocalizationValue(key), bundle: localized, locale: locale)
        return locale.identifier.replacingOccurrences(of: "-", with: "_") == "en_XA" ? "［" + value + " · " + value + "］" : value
    }
    public static func format(_ key: String, _ arguments: CVarArg..., locale: Locale = .current) -> String {
        let expanded = locale.identifier.replacingOccurrences(of: "-", with: "_") == "en_XA"
        let value = String(format: text(key, locale: expanded ? Locale(identifier: "en") : locale), locale: locale, arguments: arguments)
        return expanded ? "［" + value + " · " + value + "］" : value
    }
}
