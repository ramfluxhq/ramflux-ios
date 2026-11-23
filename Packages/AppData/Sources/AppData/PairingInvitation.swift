// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import RamfluxCore

/// The show-once invitation of `device.pair.begin`: a bearer credential for the other device.
/// It holds the token's canonical wire bytes (`InviteToken::to_wire_bytes`, RFC 8785 JSON, the form a joining
/// device reads) in an erasable buffer. It is never converted to String, Data or JSONValue here, never
/// persisted and never logged; `erase()` zeroes it and every later read sees nothing.
public final class PairingInvitation: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let operation: PairingOperation
    public let expiresAt: Date
    private let token: Mutex<[UInt8]>
    public var description: String { "PairingInvitation" }
    public var debugDescription: String { description }
    public static func == (lhs: PairingInvitation, rhs: PairingInvitation) -> Bool { lhs === rhs }
    public init(operation: PairingOperation, expiresAt: Date, token: consuming [UInt8]) {
        self.operation = operation; self.expiresAt = expiresAt; self.token = Mutex(token)
    }
    /// Reads the token bytes once per call; nil after `erase()`.
    public func withToken<T: Sendable>(_ use: (UnsafeRawBufferPointer) -> T?) -> T? {
        token.withLock { bytes in bytes.isEmpty ? nil : bytes.withUnsafeBytes { use($0) } }
    }
    public var isErased: Bool { token.withLock { $0.isEmpty } }
    public func erase() { token.withLock { Self.zero(&$0); $0.removeAll() } }
    deinit { token.withLock { Self.zero(&$0) } }
    static func zero(_ bytes: inout [UInt8]) { bytes.withUnsafeMutableBytes { if let base = $0.baseAddress { _ = memset_s(base, $0.count, 0, $0.count) } } }
}

/// Reads the sealed `device.pair.begin` frame by byte ranges. Only the non-secret fields are decoded into
/// values; the invitation token is re-encoded canonically (sorted object keys, no whitespace, scalars copied
/// verbatim) straight from the sealed buffer into the invitation's own buffer.
enum SealedPairingFrame {
    static func invitation(_ frame: SecretBytes) throws -> PairingInvitation {
        try frame.consume { raw in
            let reader = Reader(bytes: raw.bindMemory(to: UInt8.self))
            let root = try reader.value(at: 0)
            guard try reader.integer(reader.member(root, "code")) == 0, let response = try reader.member(root, "response"),
                  try reader.literal(reader.member(response, "ok")) == "true", let body = try reader.member(response, "body"),
                  let outcome = try reader.member(body, "outcome"), let tag = try reader.text(reader.member(outcome, "tag")) else {
                throw AppFailure.invalidData
            }
            guard try reader.text(reader.member(body, "schema")) == "ramflux.pairing.LocalResult.v2" else { throw AppFailure.invalidData }
            if tag == "error" {
                let code = try reader.member(outcome, "error").flatMap { try reader.text(reader.member($0, "code")) }
                throw AppFailure.pairing(PairingIssue.sdk(code) ?? .other)
            }
            guard tag == "begin", let value = try reader.member(outcome, "value"),
                  let id = try reader.text(reader.member(value, "operation_id")),
                  let generation = try reader.integer(reader.member(value, "generation")), generation >= 1,
                  let expires = try reader.integer(reader.member(value, "expires_at")),
                  let token = try reader.member(value, "invite_token") else { throw AppFailure.invalidData }
            // The SDK binds the token to the operation (`BeginResult::validate`); a mismatch is not this ceremony.
            let invitation = try reader.member(token, "invitation").flatMap { try reader.member($0, "body") }
            guard let invitation, try reader.text(reader.member(invitation, "request_id")) == id else { throw AppFailure.invalidData }
            // Reserved once: the canonical form is never longer than the source range, so no growth copy is left behind.
            var canonical: [UInt8] = []; canonical.reserveCapacity(token.count)
            do { try reader.canonical(token, into: &canonical) } catch { PairingInvitation.zero(&canonical); throw error }
            return PairingInvitation(operation: PairingOperation(id: id, generation: generation), expiresAt: Date(timeIntervalSince1970: TimeInterval(expires)), token: canonical)
        }
    }

    /// A bounded, allocation-light JSON reader over a byte buffer. Values are byte ranges.
    struct Reader {
        let bytes: UnsafeBufferPointer<UInt8>
        static let maxDepth = 32
        private func space(_ index: Int) -> Int {
            var i = index
            while i < bytes.count, [UInt8(9), 10, 13, 32].contains(bytes[i]) { i += 1 }
            return i
        }
        /// The range of the value starting at `index` (after whitespace).
        func value(at index: Int, depth: Int = 0) throws -> Range<Int> {
            guard depth < Self.maxDepth else { throw AppFailure.invalidData }
            let start = space(index)
            guard start < bytes.count else { throw AppFailure.invalidData }
            switch bytes[start] {
            case 34: return start..<(try stringEnd(start))
            case 123, 91:
                let close: UInt8 = bytes[start] == 123 ? 125 : 93
                var i = space(start + 1)
                if i < bytes.count, bytes[i] == close { return start..<(i + 1) }
                while true {
                    if close == 125 {
                        guard i < bytes.count, bytes[i] == 34 else { throw AppFailure.invalidData }
                        i = space(try stringEnd(i))
                        guard i < bytes.count, bytes[i] == 58 else { throw AppFailure.invalidData }
                        i += 1
                    }
                    i = space(try value(at: i, depth: depth + 1).upperBound)
                    guard i < bytes.count else { throw AppFailure.invalidData }
                    if bytes[i] == close { return start..<(i + 1) }
                    guard bytes[i] == 44 else { throw AppFailure.invalidData }
                    i = space(i + 1)
                }
            default:
                var i = start
                while i < bytes.count, (48...57).contains(bytes[i]) || (97...122).contains(bytes[i]) || [UInt8(45), 43, 46, 69].contains(bytes[i]) { i += 1 }
                guard i > start else { throw AppFailure.invalidData }
                return start..<i
            }
        }
        private func stringEnd(_ start: Int) throws -> Int {
            var i = start + 1
            while i < bytes.count {
                switch bytes[i] {
                case 92: i += 2
                case 34: return i + 1
                case 0..<32: throw AppFailure.invalidData
                default: i += 1
                }
            }
            throw AppFailure.invalidData
        }
        /// Object members as (key contents, value) ranges; keys must be plain ASCII without escapes and unique.
        func members(_ object: Range<Int>) throws -> [(key: Range<Int>, value: Range<Int>)] {
            guard bytes[object.lowerBound] == 123 else { throw AppFailure.invalidData }
            var result: [(key: Range<Int>, value: Range<Int>)] = []
            var i = space(object.lowerBound + 1)
            guard bytes[i] != 125 else { return [] }
            while i < object.upperBound {
                let keyEnd = try stringEnd(i)
                let key = (i + 1)..<(keyEnd - 1)
                guard key.allSatisfy({ bytes[$0] != 92 && bytes[$0] < 128 }) else { throw AppFailure.invalidData }
                i = space(keyEnd); i += 1
                let value = try value(at: i, depth: 1)
                guard !result.contains(where: { equal($0.key, key) }) else { throw AppFailure.invalidData }
                result.append((key, value))
                i = space(value.upperBound)
                if bytes[i] == 125 { break }
                i = space(i + 1)
            }
            return result
        }
        func elements(_ array: Range<Int>) throws -> [Range<Int>] {
            guard bytes[array.lowerBound] == 91 else { throw AppFailure.invalidData }
            var result: [Range<Int>] = []
            var i = space(array.lowerBound + 1)
            guard bytes[i] != 93 else { return [] }
            while i < array.upperBound {
                let value = try value(at: i, depth: 1)
                result.append(value)
                i = space(value.upperBound)
                if bytes[i] == 93 { break }
                i = space(i + 1)
            }
            return result
        }
        private func equal(_ a: Range<Int>, _ b: Range<Int>) -> Bool { a.count == b.count && zip(a, b).allSatisfy { bytes[$0] == bytes[$1] } }
        private func less(_ a: Range<Int>, _ b: Range<Int>) -> Bool {
            for (x, y) in zip(a, b) where bytes[x] != bytes[y] { return bytes[x] < bytes[y] }
            return a.count < b.count
        }
        func member(_ object: Range<Int>?, _ name: String) throws -> Range<Int>? {
            guard let object, bytes[object.lowerBound] == 123 else { return nil }
            let wanted = Array(name.utf8)
            return try members(object).first { $0.key.count == wanted.count && zip($0.key, wanted).allSatisfy { bytes[$0] == $1 } }?.value
        }
        /// A short non-secret string without escapes (ids, tags, schema names).
        func text(_ range: Range<Int>?) throws -> String? {
            guard let range, bytes[range.lowerBound] == 34, range.count <= 1026 else { return nil }
            let inner = (range.lowerBound + 1)..<(range.upperBound - 1)
            guard inner.allSatisfy({ bytes[$0] != 92 && bytes[$0] < 128 }) else { throw AppFailure.invalidData }
            return String(decoding: UnsafeBufferPointer(rebasing: bytes[inner]), as: UTF8.self)
        }
        func integer(_ range: Range<Int>?) throws -> UInt64? {
            guard let range, range.count <= 20, range.allSatisfy({ (48...57).contains(bytes[$0]) }) else { return nil }
            return UInt64(String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self))
        }
        func literal(_ range: Range<Int>?) -> String? {
            guard let range, range.count <= 5 else { return nil }
            return String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
        }
        /// RFC 8785 for the token's value space: object keys sorted (ASCII, so UTF-16 order is byte order),
        /// strings copied as the SDK escaped them, integers only (a fraction or exponent is refused).
        func canonical(_ range: Range<Int>, into output: inout [UInt8], depth: Int = 0) throws {
            guard depth < Self.maxDepth else { throw AppFailure.invalidData }
            switch bytes[range.lowerBound] {
            case 123:
                let sorted = try members(range).sorted { less($0.key, $1.key) }
                output.append(123)
                for (index, member) in sorted.enumerated() {
                    if index > 0 { output.append(44) }
                    output.append(34); output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[member.key])); output.append(34); output.append(58)
                    try canonical(member.value, into: &output, depth: depth + 1)
                }
                output.append(125)
            case 91:
                output.append(91)
                for (index, element) in try elements(range).enumerated() {
                    if index > 0 { output.append(44) }
                    try canonical(element, into: &output, depth: depth + 1)
                }
                output.append(93)
            case 34:
                output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[range]))
            default:
                let literal = range.allSatisfy { (48...57).contains(bytes[$0]) || bytes[$0] == 45 }
                guard literal || ["true", "false", "null"].contains(self.literal(range) ?? "") else { throw AppFailure.invalidData }
                output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[range]))
            }
        }
    }
}
