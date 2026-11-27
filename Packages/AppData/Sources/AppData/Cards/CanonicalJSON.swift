// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import RFLocalization

/// RFC 8785 (JCS) canonical bytes of a JSON value, as the SDK requires for surface hashes and
/// action frames: object keys sorted by UTF-16 code units, minimal string escapes, integers in
/// decimal. Non-integral numbers use the shortest round-trip form (surface values in the card
/// catalogue are integers, strings, booleans and objects).
enum CanonicalJSON {
    static func bytes(_ value: JSONValue) -> Data { Data(text(value).utf8) }
    static func text(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }
    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let flag): out += flag ? "true" : "false"
        case .unsigned(let number): out += String(number)
        case .number(let number):
            if number.rounded() == number, abs(number) < 9_007_199_254_740_992 { out += String(Int64(number)) } else { out += "\(number)" }
        case .string(let string): quote(string, into: &out)
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() { if index > 0 { out += "," }; write(item, into: &out) }
            out += "]"
        case .object(let fields):
            out += "{"
            for (index, key) in fields.keys.sorted(by: { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }).enumerated() {
                if index > 0 { out += "," }
                quote(key, into: &out); out += ":"
                write(fields[key] ?? .null, into: &out)
            }
            out += "}"
        }
    }
    private static func quote(_ string: String, into out: inout String) {
        out += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        out += "\""
    }
    /// base64url without padding of BLAKE3(domain ‖ canonical bytes).
    static func hash(_ domain: String, _ value: JSONValue) -> String {
        var digest = BLAKE3()
        digest.update(Data(domain.utf8)); digest.update(bytes(value))
        return base64URL(Data(digest.digest()))
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
