// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The App Group and Keychain access group declared in the host bundle's Info.plist (`RamfluxAppGroup`,
/// `RamfluxKeychainGroup`, set from build settings). The app and its notification extension share both.
public enum SharedGroups {
    public static func appGroup(info: [String: Any]? = Bundle.main.infoDictionary) -> String? { value("RamfluxAppGroup", info) }
    public static func keychainGroup(info: [String: Any]? = Bundle.main.infoDictionary) -> String? { value("RamfluxKeychainGroup", info) }
    private static func value(_ key: String, _ info: [String: Any]?) -> String? {
        guard let text = info?[key] as? String, !text.isEmpty, !text.contains("$(") else { return nil }
        return text
    }
}

public enum AppStorage {
    /// The data root is `ramflux/` inside the App Group container that the app and its extension share, never the
    /// app's private container. On iOS the base must be that container.
    public static func prepare(groupContainer: URL, appGroup: String? = SharedGroups.appGroup()) throws -> URL {
        guard groupContainer.isFileURL else { throw BridgeError.unsafeStoragePath }
        #if os(iOS)
        guard let appGroup, let canonical = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              groupContainer.standardizedFileURL == canonical.standardizedFileURL else { throw BridgeError.unsafeStoragePath }
        #endif
        let root = groupContainer.appendingPathComponent("ramflux", isDirectory: true)
        // The base is supplied by the application container; reject symlinks in owned paths.
        // System ancestors such as /var may legitimately resolve through an OS symlink.
        for candidate in [groupContainer, root] {
            if FileManager.default.fileExists(atPath: candidate.path),
               try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw BridgeError.unsafeStoragePath
            }
        }
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700,
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #endif
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: attributes)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: root.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var protectedRoot = root; try protectedRoot.setResourceValues(values)
        return root
    }
    /// Apply after foreground open as well: SQLite can recreate WAL/shm files.
    public static func protectDatabaseFiles(in root: URL) throws {
        guard let files = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else {
            throw BridgeError.unsafeStoragePath
        }
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw BridgeError.unsafeStoragePath }
            if values.isRegularFile == true || values.isDirectory == true {
                var attributes: [FileAttributeKey: Any] = [.posixPermissions: values.isDirectory == true ? 0o700 : 0o600]
                #if os(iOS)
                attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
                #endif
                try FileManager.default.setAttributes(attributes, ofItemAtPath: file.path)
            }
        }
    }
}
