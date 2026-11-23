// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The one catalog lookup for every package. Each package passes its own
/// resource bundle; the lookup picks the best localisation for the locale and
/// falls back to the development language (English) for any key that the
/// chosen localisation lacks, so a missing translation never shows the raw key.
/// The localisation lint guarantees that every key exists in English.
public enum CatalogLookup {
    public static let developmentLanguage = "en"

    /// The expanded pseudo-locale doubles every string inside brackets.
    public static func isExpanded(_ locale: Locale) -> Bool {
        locale.identifier.replacingOccurrences(of: "-", with: "_") == "en_XA"
    }

    /// The localisation that holds `key` for `locale`. When the locale has no
    /// translation of the key, the English entry is returned together with the
    /// English locale, so plural rules and formatting match the English text.
    public static func resolve(_ key: String, in source: Bundle, locale: Locale) -> (bundle: Bundle, locale: Locale) {
        let preference = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let language = Bundle.preferredLocalizations(from: source.localizations, forPreferences: [preference]).first ?? developmentLanguage
        let english = Locale(identifier: developmentLanguage)
        let localized = localization(language, in: source) ?? source
        if contains(key, in: localized) {
            let sameLanguage = language == developmentLanguage ? locale.language.languageCode == english.language.languageCode : true
            return (localized, sameLanguage ? locale : english)
        }
        return (localization(developmentLanguage, in: source) ?? localized, english)
    }

    public static func text(_ key: String, bundle source: Bundle, locale: Locale) -> String {
        let resolved = resolve(key, in: source, locale: locale)
        let value = String(localized: String.LocalizationValue(key), bundle: resolved.bundle, locale: resolved.locale)
        return isExpanded(locale) ? expand(value) : value
    }

    /// Formats a catalog entry; the expanded pseudo-locale formats the English entry.
    public static func format(_ key: String, _ arguments: [CVarArg], bundle source: Bundle, locale: Locale) -> String {
        let expanded = isExpanded(locale)
        let lookup = expanded ? Locale(identifier: developmentLanguage) : locale
        let resolved = resolve(key, in: source, locale: lookup)
        let template = String(localized: String.LocalizationValue(key), bundle: resolved.bundle, locale: resolved.locale)
        let value = String(format: template, locale: expanded ? locale : resolved.locale, arguments: arguments)
        return expanded ? expand(value) : value
    }

    /// Composes a catalog format with typed arguments (`RFSentence`): untrusted text is
    /// isolated, identifiers stay left to right. The expanded pseudo-locale composes the
    /// English entry and expands the result once.
    public static func sentence(_ key: String, _ arguments: [RFTextArgument], bundle source: Bundle, locale: Locale) -> String {
        let expanded = isExpanded(locale)
        let lookup = expanded ? Locale(identifier: developmentLanguage) : locale
        let resolved = resolve(key, in: source, locale: lookup)
        let template = String(localized: String.LocalizationValue(key), bundle: resolved.bundle, locale: resolved.locale)
        let value = RFSentence.compose(template, arguments, locale: expanded ? locale : resolved.locale)
        return expanded ? expand(value) : value
    }

    /// Pseudo-localisation for expansion review, not translation assembly.
    public static func expand(_ value: String) -> String {
        "［" + value + " · " + value + "］"
    }

    private static func localization(_ language: String, in source: Bundle) -> Bundle? {
        source.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private static func contains(_ key: String, in bundle: Bundle) -> Bool {
        let missing = "\u{0}rf.catalog.missing"
        return bundle.localizedString(forKey: key, value: missing, table: nil) != missing
    }
}
