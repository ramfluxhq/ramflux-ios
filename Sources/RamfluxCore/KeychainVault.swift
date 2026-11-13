// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Security
import LocalAuthentication
import Darwin

/// App-private keychain items. No access group, synchronization, file fallback, or shared DB.
public actor KeychainVault {
    private let service: String
    private let keychain: any KeychainAccess
    public init(service: String = "org.ramflux.core.vault") { self.service = service; keychain = SecurityKeychain() }
    init(service: String, keychain: any KeychainAccess) { self.service = service; self.keychain = keychain }
    private func query(_ account: String) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true, kSecUseAuthenticationContext as String: context]
    }
    public func store(_ secret: SecretBytes, account: String) throws {
        guard !account.isEmpty, account.utf8.count <= 256 else { throw BridgeError.invalidInput }
        try secret.consume { bytes in
            guard let data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
                bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, kCFAllocatorNull) else {
                throw BridgeError.invalidResponse
            }
            var attributes = query(account)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecValueData as String] = data
            let status = keychain.add(attributes as CFDictionary)
            if status == errSecDuplicateItem {
                let updates: [String: Any] = [kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
                let updated = keychain.update(query(account) as CFDictionary, attributes: updates as CFDictionary)
                guard updated == errSecSuccess else { throw BridgeError.keychain(updated) }
            } else if status != errSecSuccess { throw BridgeError.keychain(status) }
        }
    }
    /// An entry without its existing database is refused; never create state under its identity.
    public func load(account: String, existingDatabase: URL) throws -> SecretBytes {
        guard FileManager.default.fileExists(atPath: existingDatabase.path) else {
            var metadata = query(account)
            metadata[kSecReturnAttributes as String] = true
            let status = keychain.copy(metadata as CFDictionary, result: nil)
            if status == errSecSuccess { throw BridgeError.orphanedVault }
            if status == errSecItemNotFound { throw BridgeError.missingVault }
            throw BridgeError.keychain(status)
        }
        var result: CFTypeRef?
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = keychain.copy(attributes as CFDictionary, result: &result)
        guard status != errSecItemNotFound else { throw BridgeError.missingVault }
        guard status == errSecSuccess else { throw BridgeError.keychain(status) }
        guard let result, CFGetTypeID(result) == CFDataGetTypeID(), let data = result as? NSData else { throw BridgeError.invalidResponse }
        // The immutable Security-owned result is borrowed directly. No COW Data bridge or
        // misleading claim that resetBytes erased the provider's returned allocation.
        return try SecretBytes(copying: UnsafeRawBufferPointer(start: data.bytes, count: data.length))
    }
    public func remove(account: String) throws {
        let status = keychain.delete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeError.keychain(status) }
    }
}
