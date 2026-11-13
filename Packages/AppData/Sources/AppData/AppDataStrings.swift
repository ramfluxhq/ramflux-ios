// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum AppDataStrings {
    public static func status(_ value: String?, locale: Locale = .current) -> String {
        let key: String = switch value {
        case "backup": "status.backup"
        case "restore": "status.restore"
        case "preparing": "status.preparing"
        case "writing": "status.writing"
        case "verifying": "status.verifying"
        case "verified": "status.verified"
        case "installing": "status.installing"
        case "done": "status.done"
        case "failed": "status.failed"
        case "cancelled": "status.cancelled"
        case "pending": "status.pending"
        case "accepted": "status.accepted"
        case "declined": "status.declined"
        case "blocked": "status.blocked"
        case "manual": "status.manual"
        case "auto_accept": "status.auto_accept"
        case "accept": "status.accept"
        case "decline": "status.decline"
        case "block": "status.block"
        case "sent": "status.sent"
        case "delivered": "status.delivered"
        case "read": "status.read"
        case "unavailable": "status.unavailable"
        default: "status.unavailable"
        }
        return text(key, locale: locale)
    }
    public static func text(_ key: String, locale: Locale = .current) -> String {
        let source: Bundle = .module
        let language = Bundle.preferredLocalizations(from: source.localizations, forPreferences: [locale.identifier.replacingOccurrences(of: "_", with: "-")]).first ?? "en"
        let localized = source.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? source
        let value = String(localized: String.LocalizationValue(key), bundle: localized, locale: locale)
        return locale.identifier.replacingOccurrences(of: "-", with: "_") == "en_XA" ? "［" + value + " · " + value + "］" : value
    }
    public static func format(_ key: String, _ arguments: CVarArg..., locale: Locale = .current) -> String {
        String(format: text(key, locale: locale), locale: locale, arguments: arguments)
    }
}
