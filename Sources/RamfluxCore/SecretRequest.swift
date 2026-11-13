// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CRamflux

public struct SecretRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let request: CoreRequest
    let json: SecretBytes
    public var description: String { "SecretRequest" }
    public var debugDescription: String { "SecretRequest" }
    public init(request: CoreRequest, fields: [String: SecretField]) throws {
        defer { fields.values.forEach { $0.erase() } }
        guard case .object(let body) = request.body, fields.count <= 4, Set(fields.keys).isDisjoint(with: body.keys) else { throw BridgeError.invalidInput }
        // Build the entire ABI request in the same erased allocation.
        let envelope = request.envelope()
        guard case .object(var outer) = envelope else { throw BridgeError.invalidInput }
        outer.removeValue(forKey: "body")
        let envelopeBytes = try JSONValue.object(outer).encoded()
        var metadata = try request.body.encodedRequest()
        defer { metadata.resetBytes(in: 0..<metadata.count) }
        let capacity = CoreLimits.frameBytes
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
        defer { rf_secure_zero(buffer, capacity); buffer.deallocate() }
        var count = 0
        func append(_ byte: UInt8) throws {
            guard count < capacity else { throw BridgeError.responseTooLarge }
            buffer.storeBytes(of: byte, toByteOffset: count, as: UInt8.self); count += 1
        }
        for byte in envelopeBytes.dropLast() { try append(byte) }
        for byte in Array(",\"body\":".utf8) { try append(byte) }
        for byte in metadata.dropLast() { try append(byte) }
        var needsComma = !body.isEmpty
        for key in fields.keys.sorted() {
            if needsComma { try append(44) }; needsComma = true
            let keyBytes = try JSONEncoder().encode(key)
            for byte in keyBytes { try append(byte) }; try append(58)
            guard let field = fields[key] else { throw BridgeError.invalidInput }
            func text(_ secret: SecretBytes) throws {
                try append(34)
                try secret.consume { bytes in
                    for byte in bytes {
                        switch byte {
                        case 34, 92: try append(92); try append(byte)
                        case 0...31:
                            for value in String(format: "\\u%04x", byte).utf8 { try append(value) }
                        default: try append(byte)
                        }
                    }
                }
                try append(34)
            }
            switch field {
            case .text(let secret): try text(secret)
            case .words(let words):
                guard words.count == 3 else { throw BridgeError.invalidInput }
                try append(91)
                for (index, word) in words.enumerated() { if index > 0 { try append(44) }; try text(word) }
                try append(93)
            }
        }
        try append(125); try append(125)
        self.request = request
        json = try SecretBytes(copying: UnsafeRawBufferPointer(start: buffer, count: count))
    }
}
