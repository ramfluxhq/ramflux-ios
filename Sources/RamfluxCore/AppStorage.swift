// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

public enum AppStorage {
    /// The application passes its own Application Support directory, never an App Group.
    public static func prepare(applicationSupport: URL) throws -> URL {
        guard applicationSupport.isFileURL else { throw BridgeError.unsafeStoragePath }
        #if os(iOS)
        let canonical = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        guard applicationSupport.standardizedFileURL == canonical.standardizedFileURL else { throw BridgeError.unsafeStoragePath }
        #endif
        let root = applicationSupport.appendingPathComponent("ramflux", isDirectory: true)
        // The base is supplied by the application container; reject symlinks in owned paths.
        // System ancestors such as /var may legitimately resolve through an OS symlink.
        for candidate in [applicationSupport, root] {
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
        #if os(iOS)
        let files = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw BridgeError.unsafeStoragePath }
            if values.isRegularFile == true {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                                                        .posixPermissions: 0o600], ofItemAtPath: file.path)
            }
        }
        #endif
    }
}
