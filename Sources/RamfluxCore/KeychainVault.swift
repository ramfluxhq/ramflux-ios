// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Security
import Darwin

/// App-private keychain items. No access group, synchronization, file fallback, or shared DB.
public actor KeychainVault {
    private let service: String
    public init(service: String = "org.ramflux.core.vault") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    public func store(_ secret: SecretBytes, account: String) throws {
        guard !account.isEmpty, account.utf8.count <= 256 else { throw BridgeError.invalidInput }
        try secret.consume { bytes in
            var data = Data(bytes)
            defer { data.resetBytes(in: 0..<data.count) }
            var attributes = query(account)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecValueData as String] = data
            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecDuplicateItem {
                let updates: [String: Any] = [kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
                let updated = SecItemUpdate(query(account) as CFDictionary, updates as CFDictionary)
                guard updated == errSecSuccess else { throw BridgeError.keychain(updated) }
            } else if status != errSecSuccess { throw BridgeError.keychain(status) }
        }
    }
    /// An entry without its existing database is refused; never create state under its identity.
    public func load(account: String, existingDatabase: URL) throws -> SecretBytes {
        guard FileManager.default.fileExists(atPath: existingDatabase.path) else {
            var metadata = query(account)
            metadata[kSecReturnAttributes as String] = true
            metadata[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            let status = SecItemCopyMatching(metadata as CFDictionary, nil)
            if status == errSecSuccess { throw BridgeError.orphanedVault }
            if status == errSecItemNotFound { throw BridgeError.missingVault }
            throw BridgeError.keychain(status)
        }
        var result: CFTypeRef?
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw BridgeError.missingVault }
        guard status == errSecSuccess else { throw BridgeError.keychain(status) }
        guard var data = result as? Data else { throw BridgeError.invalidResponse }
        defer { data.resetBytes(in: 0..<data.count) }
        return try data.withUnsafeBytes { try SecretBytes(copying: $0) }
    }
    public func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeError.keychain(status) }
    }
}
