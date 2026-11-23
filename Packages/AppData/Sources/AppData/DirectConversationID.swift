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
        return "dm:" + base64url(BLAKE3.hash(transcript))
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
