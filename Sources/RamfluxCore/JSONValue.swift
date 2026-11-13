// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// Transport JSON only. Domain/schema validation belongs to the SDK. Exact u64 values use strings.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), unsigned(UInt64), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        guard decoder.codingPath.count <= 32 else { throw BridgeError.invalidResponse }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode(UInt64.self), v > 9_007_199_254_740_991 { self = .unsigned(v) }
        else { self = .number(try c.decode(Double.self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .unsigned(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue? { if case .object(let v) = self { v[key] } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= CoreLimits.frameBytes else { throw BridgeError.responseTooLarge }
        try Self.checkBounds(bytes)
        return bytes
    }
    static func decode(_ bytes: Data) throws -> JSONValue {
        guard bytes.count <= CoreLimits.frameBytes else { throw BridgeError.responseTooLarge }
        try checkBounds(bytes)
        return try JSONDecoder().decode(Self.self, from: bytes)
    }
    private static func checkBounds(_ data: Data) throws {
        var depth = 0, nodes = 0
        var quoted = false, escaped = false, primitive = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
                continue
            }
            switch byte {
            case 34: quoted = true; primitive = false; nodes += 1
            case 91, 123: depth += 1; nodes += 1; primitive = false
            case 93, 125: depth -= 1; primitive = false
            case 44, 58, 9, 10, 13, 32: primitive = false
            default: if !primitive { nodes += 1; primitive = true }
            }
            guard depth <= 32, depth >= 0, nodes <= 4096 else { throw BridgeError.invalidResponse }
        }
    }

}

public enum CoreLimits {
    public static let frameBytes = 1_048_576
    public static let eventBuffer = 64
    public static let pollMilliseconds: UInt32 = 100
}
