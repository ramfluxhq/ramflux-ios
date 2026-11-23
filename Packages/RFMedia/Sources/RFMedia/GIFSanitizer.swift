// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// Removes metadata blocks from a GIF without re-encoding it (media design 4.2): comment
/// extensions, unknown extensions and every application extension except looping (`NETSCAPE2.0`,
/// `ANIMEXTS1.0`) and the ICC colour profile (`ICCRGBG1012`, kept like the colour profile of
/// re-encoded photos) are dropped. XMP packets travel as application extensions and go with them.
/// Every frame, palette, graphic control and plain-text block is copied byte for byte, so the
/// animation is pixel-identical. Anything after the trailer is dropped. A malformed or truncated
/// file returns nil and is not sent as an animated image.
public enum GIFSanitizer {
    static let keptApplications: Set<String> = ["NETSCAPE2.0", "ANIMEXTS1.0", "ICCRGBG1012"]

    public static func strip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 13, bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) else { return nil }
        var out = [UInt8](); out.reserveCapacity(bytes.count)
        var index = 13
        out.append(contentsOf: bytes[0..<13])
        if bytes[10] & 0x80 != 0 {
            let table = 3 << (Int(bytes[10] & 0x07) + 1)
            guard index + table <= bytes.count else { return nil }
            out.append(contentsOf: bytes[index..<index + table]); index += table
        }
        while index < bytes.count {
            switch bytes[index] {
            case 0x3B:
                out.append(0x3B)
                return Data(out)
            case 0x2C:
                guard index + 10 <= bytes.count else { return nil }
                var end = index + 10
                if bytes[index + 9] & 0x80 != 0 { end += 3 << (Int(bytes[index + 9] & 0x07) + 1) }
                end += 1 // LZW minimum code size
                guard end <= bytes.count, let blocks = subBlocks(bytes, from: end) else { return nil }
                out.append(contentsOf: bytes[index..<blocks]); index = blocks
            case 0x21:
                guard index + 2 <= bytes.count, let blocks = subBlocks(bytes, from: index + 2) else { return nil }
                if keep(bytes, label: bytes[index + 1], at: index + 2) { out.append(contentsOf: bytes[index..<blocks]) }
                index = blocks
            default:
                return nil
            }
        }
        return nil
    }

    /// The index after the zero-length terminator of the sub-block chain starting at `from`.
    private static func subBlocks(_ bytes: [UInt8], from: Int) -> Int? {
        var index = from
        while index < bytes.count {
            let length = Int(bytes[index])
            index += 1
            if length == 0 { return index }
            index += length
        }
        return nil
    }

    private static func keep(_ bytes: [UInt8], label: UInt8, at index: Int) -> Bool {
        switch label {
        case 0xF9, 0x01: return true
        case 0xFF:
            guard index < bytes.count, bytes[index] == 11, index + 12 <= bytes.count else { return false }
            return keptApplications.contains(String(decoding: bytes[index + 1...index + 11], as: UTF8.self))
        default: return false
        }
    }
}
