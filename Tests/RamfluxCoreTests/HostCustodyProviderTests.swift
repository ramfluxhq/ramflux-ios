// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Security
import Testing
import CRamflux
@testable import RamfluxCore
private final class ProviderKeychain: KeychainAccess {
    let stored = Mutex<Data?>(nil)
    let policy = Mutex(false)
    func add(_ query: CFDictionary) -> OSStatus {
        let values = query as NSDictionary
        policy.withLock { $0 = values[kSecAttrAccessible] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String && values[kSecAttrSynchronizable] as? Bool == false }
        return stored.withLock { data in
            guard data == nil else { return errSecDuplicateItem }
            guard let incoming = values[kSecValueData] as? Data else { return errSecDecode }; data = incoming; return errSecSuccess
        }
    }
    func copy(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        stored.withLock { data in guard let data else { return errSecItemNotFound }; result?.pointee = data as CFData; return errSecSuccess }
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { errSecAuthFailed }
    func delete(_ query: CFDictionary) -> OSStatus { stored.withLock { $0 = nil }; return errSecSuccess }
}
struct HostCustodyProviderTests {
    @Test func protectedProviderRoundTripBoundsAndNoOverwritePolicy() {
        let keychain = ProviderKeychain(), seed = [UInt8](repeating: 7, count: 32), reference = Array("test-vault-reference".utf8)
        let provider = HostCustodyProvider(service: "test-only", access: keychain)
        var request = RamfluxV2CustodyRequest(operation: 0, reference: nil, reference_len: 0, input: nil, input_len: 0, output: nil, output_capacity: 0, output_len: 99)
        #expect(provider.invoke(&request) == 0); #expect(request.output_len == 0)
        reference.withUnsafeBufferPointer { ref in seed.withUnsafeBufferPointer { bytes in
            request = RamfluxV2CustodyRequest(operation: 1, reference: ref.baseAddress, reference_len: ref.count, input: bytes.baseAddress, input_len: bytes.count, output: nil, output_capacity: 0, output_len: 0)
            #expect(provider.invoke(&request) == 0); #expect(keychain.policy.withLock { $0 })
            #expect(provider.invoke(&request) == 2)
            var output = [UInt8](repeating: 0, count: 32)
            output.withUnsafeMutableBufferPointer { buffer in
                request.operation = 2; request.input = nil; request.input_len = 0; request.output = buffer.baseAddress; request.output_capacity = 31
                #expect(provider.invoke(&request) == 2); #expect(request.output_len == 0)
                request.output_capacity = 32
                #expect(provider.invoke(&request) == 0); #expect(request.output_len == 32)
            }
            #expect(output == seed)
            request.operation = 3; #expect(provider.invoke(&request) == 0)
        } }
    }
}
