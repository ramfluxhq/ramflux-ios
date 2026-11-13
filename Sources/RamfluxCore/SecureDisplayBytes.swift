// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import CRamflux

/// Repaintable secret presentation storage. Never converted to String, Data or a transport JSON tree.
public final class SecureDisplayBytes: Sendable {
    private let bytes: Mutex<[UInt8]>
    public init(phraseFrame: SecretBytes) throws {
        var phrase: [UInt8] = try phraseFrame.consume { input in
            let buffer = input.bindMemory(to: UInt8.self)
            let marker = Array("\"phrase\"".utf8)
            var match: Int?
            guard buffer.count >= marker.count else { throw BridgeError.invalidResponse }
            for start in 0...(buffer.count - marker.count) {
                if marker.indices.allSatisfy({ buffer[start + $0] == marker[$0] }) {
                    guard match == nil else { throw BridgeError.invalidResponse }; match = start + marker.count
                }
            }
            guard var index = match else { throw BridgeError.invalidResponse }
            func skip() { while index < buffer.count, [UInt8(9),10,13,32].contains(buffer[index]) { index += 1 } }
            skip(); guard index < buffer.count, buffer[index] == 58 else { throw BridgeError.invalidResponse }; index += 1
            skip(); guard index < buffer.count, buffer[index] == 34 else { throw BridgeError.invalidResponse }; index += 1
            let start = index
            while index < buffer.count, buffer[index] != 34 {
                guard (97...122).contains(buffer[index]) || buffer[index] == 32, index - start < 512 else { throw BridgeError.invalidResponse }
                index += 1
            }
            guard index < buffer.count, index > start else { throw BridgeError.invalidResponse }
            return Array(buffer[start..<index])
        }
        bytes = Mutex(phrase)
        phrase.removeAll()
    }
    public func withBytes(_ render: (UnsafeRawBufferPointer) -> Void) {
        bytes.withLock { value in value.withUnsafeBytes { if !$0.isEmpty { render($0) } } }
    }
    public func erase() { bytes.withLock { value in value.withUnsafeMutableBytes { rf_secure_zero($0.baseAddress, $0.count) }; value.removeAll() } }
    deinit { bytes.withLock { value in value.withUnsafeMutableBytes { rf_secure_zero($0.baseAddress, $0.count) } } }
}
