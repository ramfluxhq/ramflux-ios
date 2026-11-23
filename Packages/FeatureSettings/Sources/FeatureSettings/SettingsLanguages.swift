// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
/// The fifteen launch languages (master plan) and which of them have a translated catalog. Only translated
/// languages ship in `CFBundleLocalizations`; iOS picks the per-app language in the app's system settings.
enum SettingsLanguages {
    static let launch = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "pt-BR", "ru", "ar", "hi", "id", "tr", "it"]
    /// Launch languages whose catalogs are present in this package (the catalogs' `zh-CN` is Simplified Chinese).
    static var translated: Set<String> {
        let shipped = Set(Bundle.module.localizations.map { $0 == "zh-CN" ? "zh-Hans" : $0 })
        return Set(launch.filter { shipped.contains($0) })
    }
    static func isCurrent(_ identifier: String, locale: Locale) -> Bool {
        let language = locale.language
        let traditional = language.script == .hanTraditional || (language.script == nil && ["TW", "HK", "MO"].contains(language.region?.identifier ?? ""))
        switch identifier {
        case "zh-Hans": return language.languageCode == .chinese && !traditional
        case "zh-Hant": return language.languageCode == .chinese && traditional
        case "pt-BR": return language.languageCode == .portuguese
        default: return language.languageCode?.identifier == identifier
        }
    }
}
