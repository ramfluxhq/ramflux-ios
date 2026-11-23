// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
/// The SDK's direct conversation id for two account roots (`ramflux-protocol` `message/dm_scope.rs`):
/// `"dm:" + base64url(BLAKE3(lp(DOMAIN) || lp(lower root) || lp(higher root)))`, where `lp` prefixes each
/// field with its length as a big-endian u32 and the roots are ordered by their bytes. The SDK creates the
/// conversation under this id for an accepted contact (`ensure_direct_conversation`); the app only derives
/// it to open the right chat and never invents a conversation the SDK would not create.
public enum DirectConversationID {
    static let domain = "ramflux.message.dm_conversation.v1"
    /// Nil when either value is not a canonical root anchor (43 base64url characters of 32 bytes) or both are equal.
    public static func derive(_ first: String, _ second: String) -> String? {
        guard canonicalAnchor(first), canonicalAnchor(second), first != second else { return nil }
        let (low, high) = Array(first.utf8).lexicographicallyPrecedes(Array(second.utf8)) ? (first, second) : (second, first)
        var transcript: [UInt8] = []
        for field in [domain, low, high] {
            let bytes = Array(field.utf8)
            withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { transcript.append(contentsOf: $0) }
            transcript.append(contentsOf: bytes)
        }
        guard let digest = BLAKE3.hashSingleChunk(transcript) else { return nil }
        return "dm:" + base64url(digest)
    }
    static func canonicalAnchor(_ value: String) -> Bool {
        guard value.utf8.count == 43, value.utf8.allSatisfy({ $0 < 0x80 }) else { return false }
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); padded += "="
        guard let bytes = Data(base64Encoded: padded), bytes.count == 32 else { return false }
        return base64url(Array(bytes)) == value
    }
    static func base64url(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
/// BLAKE3 for inputs of at most one chunk (1024 bytes), enough for the fixed-size DM transcript.
/// Verified against the reference implementation's outputs in `DirectConversationIDTests`.
enum BLAKE3 {
    private static let iv: [UInt32] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
    private static let permutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
    private static let chunkStart: UInt32 = 1, chunkEnd: UInt32 = 2, root: UInt32 = 8
    static func hashSingleChunk(_ input: [UInt8]) -> [UInt8]? {
        guard input.count <= 1024 else { return nil }
        var chaining = iv
        let blocks = max(1, (input.count + 63) / 64)
        for index in 0..<blocks {
            let start = index * 64, end = min(start + 64, input.count)
            var block = [UInt8](repeating: 0, count: 64)
            if start < end { block.replaceSubrange(0..<(end - start), with: input[start..<end]) }
            let words = (0..<16).map { word in (0..<4).reduce(UInt32(0)) { $0 | UInt32(block[word * 4 + $1]) << (8 * UInt32($1)) } }
            var flags: UInt32 = index == 0 ? chunkStart : 0
            if index == blocks - 1 { flags |= chunkEnd | root }
            chaining = Array(compress(chaining, words, blockLength: UInt32(end - start), flags: flags).prefix(8))
        }
        return chaining.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * UInt32($0))) } }
    }
    private static func compress(_ chaining: [UInt32], _ block: [UInt32], blockLength: UInt32, flags: UInt32) -> [UInt32] {
        var state = chaining + Array(iv.prefix(4)) + [0, 0, blockLength, flags]
        var message = block
        for round in 0..<7 {
            mix(&state, message)
            if round < 6 { message = permutation.map { message[$0] } }
        }
        for index in 0..<8 { state[index] ^= state[index + 8]; state[index + 8] ^= chaining[index] }
        return state
    }
    private static func mix(_ s: inout [UInt32], _ m: [UInt32]) {
        g(&s, 0, 4, 8, 12, m[0], m[1]); g(&s, 1, 5, 9, 13, m[2], m[3]); g(&s, 2, 6, 10, 14, m[4], m[5]); g(&s, 3, 7, 11, 15, m[6], m[7])
        g(&s, 0, 5, 10, 15, m[8], m[9]); g(&s, 1, 6, 11, 12, m[10], m[11]); g(&s, 2, 7, 8, 13, m[12], m[13]); g(&s, 3, 4, 9, 14, m[14], m[15])
    }
    private static func g(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
        s[a] = s[a] &+ s[b] &+ x; s[d] = (s[d] ^ s[a]).rotatedRight(16)
        s[c] = s[c] &+ s[d]; s[b] = (s[b] ^ s[c]).rotatedRight(12)
        s[a] = s[a] &+ s[b] &+ y; s[d] = (s[d] ^ s[a]).rotatedRight(8)
        s[c] = s[c] &+ s[d]; s[b] = (s[b] ^ s[c]).rotatedRight(7)
    }
}
private extension UInt32 {
    func rotatedRight(_ count: UInt32) -> UInt32 { (self >> count) | (self << (32 - count)) }
}
