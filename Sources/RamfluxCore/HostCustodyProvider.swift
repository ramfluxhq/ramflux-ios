// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Security
import LocalAuthentication
import CRamflux

/// Synchronous, thread-safe protected storage callback. SDK-owned pointers never escape a call.
public final class HostCustodyProvider: Sendable {
    private let service: String
    private let access: any KeychainAccess
    public convenience init(service: String = "org.ramflux.primary-vault") { self.init(service: service, access: SecurityKeychain()) }
    init(service: String, access: any KeychainAccess) { self.service = service; self.access = access }
    func table() -> RamfluxV2CustodyProvider {
        let context = UInt64(UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque()))
        return RamfluxV2CustodyProvider(abi_version: 1, context: context, retain: { token in
            guard let pointer = UnsafeRawPointer(bitPattern: UInt(token)) else { return }
            _ = Unmanaged<HostCustodyProvider>.fromOpaque(pointer).retain()
        }, release: { token in
            guard let pointer = UnsafeRawPointer(bitPattern: UInt(token)) else { return }
            Unmanaged<HostCustodyProvider>.fromOpaque(pointer).release()
        }, invoke: { token, request in
            guard let pointer = UnsafeRawPointer(bitPattern: UInt(token)), let request else { return 6 }
            return Unmanaged<HostCustodyProvider>.fromOpaque(pointer).takeUnretainedValue().invoke(request)
        })
    }
    private func query(_ reference: String) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: reference, kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true, kSecUseAuthenticationContext as String: context]
    }
    private func status(_ status: OSStatus) -> Int32 {
        switch status { case errSecSuccess: 0; case errSecItemNotFound: 1; case errSecDuplicateItem, errSecDecode: 2
        case errSecAuthFailed, errSecMissingEntitlement: 3; case errSecInteractionNotAllowed: 4; default: 6 }
    }
    func invoke(_ pointer: UnsafeMutablePointer<RamfluxV2CustodyRequest>) -> Int32 {
        pointer.pointee.output_len = 0
        let request = pointer.pointee
        guard request.reference_len <= 128, request.input_len <= 4096, request.output_capacity <= 4096 else { return 2 }
        if request.operation == 0 {
            var metadata = query("preflight"); metadata[kSecReturnAttributes as String] = true
            let result = access.copy(metadata as CFDictionary, result: nil)
            return result == errSecItemNotFound ? 0 : status(result)
        }
        guard let reference = request.reference, request.reference_len > 0,
              let name = String(bytes: UnsafeBufferPointer(start: reference, count: request.reference_len), encoding: .utf8),
              !name.contains("\0") else { return 2 }
        if request.operation == 3 {
            let result = access.delete(query(name) as CFDictionary)
            return result == errSecItemNotFound ? 0 : status(result)
        }
        if [UInt32(1), 4, 6].contains(request.operation) {
            let expected = request.operation == 1 ? 32 : (request.operation == 4 ? 64 : request.input_len)
            guard request.input_len == expected, expected > 0, let input = request.input,
                  let data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, input, request.input_len, kCFAllocatorNull) else { return 2 }
            var attributes = query(name)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecValueData as String] = data
            // Never overwrite an existing identity seed under the same vault reference.
            return status(access.add(attributes as CFDictionary))
        }
        guard [UInt32(2), 5, 7].contains(request.operation), let output = request.output else { return 2 }
        var attributes = query(name); attributes[kSecReturnData as String] = true; attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let code = access.copy(attributes as CFDictionary, result: &result)
        guard code == errSecSuccess else { return status(code) }
        guard let result, CFGetTypeID(result) == CFDataGetTypeID(), let data = result as? NSData,
              data.length > 0, data.length <= request.output_capacity,
              (request.operation != 2 || data.length == 32), (request.operation != 5 || data.length == 64) else { return 2 }
        UnsafeMutableRawPointer(output).copyMemory(from: data.bytes, byteCount: data.length)
        pointer.pointee.output_len = data.length
        return 0
    }
}
