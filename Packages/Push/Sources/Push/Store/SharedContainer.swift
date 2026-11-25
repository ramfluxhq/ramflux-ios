// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The App Group and Keychain access group the app and its extension share. Both identifiers come from the host
/// bundle's Info.plist (build settings in project.yml), so a different team or registration changes no source.
public enum SharedContainer {
    public static func appGroup(info: [String: Any]? = Bundle.main.infoDictionary) -> String? { value("RamfluxAppGroup", info) }
    public static func keychainGroup(info: [String: Any]? = Bundle.main.infoDictionary) -> String? { value("RamfluxKeychainGroup", info) }
    /// The shared container directory, or nil when the group is not declared or not granted to this process.
    public static func containerURL(info: [String: Any]? = Bundle.main.infoDictionary) -> URL? {
        appGroup(info: info).flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }
    private static func value(_ key: String, _ info: [String: Any]?) -> String? {
        guard let text = info?[key] as? String, !text.isEmpty, !text.contains("$(") else { return nil }
        return text
    }
}
