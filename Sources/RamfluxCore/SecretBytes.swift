// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import CRamflux

/// Non-Codable, single-use secret storage. The private byte array never escapes or shares
/// its backing storage. Consuming or dropping it explicitly erases that allocation.
/// Caller-created and operating-system copies are outside this guarantee.
public final class SecretBytes: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private struct Storage: Sendable { var bytes: [UInt8]; var consumed = false }
    private let storage: Mutex<Storage>
    public var description: String { "SecretBytes" }
    public var debugDescription: String { "SecretBytes" }
    public convenience init(copying bytes: UnsafeRawBufferPointer) throws {
        try self.init(copying: bytes, maximumBytes: CoreLimits.frameBytes)
    }
    init(copying bytes: UnsafeRawBufferPointer, maximumBytes: Int) throws {
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw BridgeError.invalidInput }
        storage = Mutex(Storage(bytes: Array(bytes)))
    }
    public func consume<T: Sendable>(_ use: (UnsafeRawBufferPointer) throws -> T) throws -> T {
        try storage.withLock { state in
            guard !state.consumed else { throw BridgeError.secretConsumed }
            state.consumed = true
            return try state.bytes.withUnsafeMutableBytes { buffer in
                defer { rf_secure_zero(buffer.baseAddress, buffer.count) }
                return try use(UnsafeRawBufferPointer(buffer))
            }
        }
    }
    var byteCount: Int { storage.withLock { $0.bytes.count } }
    var isErased: Bool { storage.withLock { $0.consumed && $0.bytes.allSatisfy { $0 == 0 } } }
    public func erase() {
        storage.withLock { state in
            state.bytes.withUnsafeMutableBytes { rf_secure_zero($0.baseAddress, $0.count) }
            state.consumed = true
        }
    }
    deinit { storage.withLock { $0.bytes.withUnsafeMutableBytes { rf_secure_zero($0.baseAddress, $0.count) } } }
}
