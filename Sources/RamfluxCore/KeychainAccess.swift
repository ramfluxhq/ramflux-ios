// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Security
import Foundation

protocol KeychainAccess: Sendable {
    func add(_ query: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func copy(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}
struct SecurityKeychain: KeychainAccess {
    func add(_ query: CFDictionary) -> OSStatus { SecItemAdd(query, nil) }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { SecItemUpdate(query, attributes) }
    func copy(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus { SecItemCopyMatching(query, result) }
    func delete(_ query: CFDictionary) -> OSStatus { SecItemDelete(query) }
}
