// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import ImageIO

/// Decides the renderer from the bytes, never from the declared type or file name. Only formats
/// the OS decoders handle are rendered inline; everything else is a file.
public enum MediaFormat: String, Sendable, Equatable {
    case jpeg, png, gif, webp, heic, avif, mp4, quicktime, unknown
    public var isImage: Bool { [.jpeg, .png, .gif, .webp, .heic, .avif].contains(self) }
    public var isVideo: Bool { self == .mp4 || self == .quicktime }
}

public enum MediaSniffer {
    /// The format from the first bytes of a file.
    public static func format(of header: Data) -> MediaFormat {
        let bytes = [UInt8](header.prefix(32))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool { bytes.count >= offset + prefix.count && Array(bytes[offset..<(offset + prefix.count)]) == prefix }
        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return .gif }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) { return .webp }
        if starts(Array("ftyp".utf8), at: 4), bytes.count >= 12 {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            if ["heic", "heix", "hevc", "heim", "heis", "mif1", "msf1"].contains(brand) { return .heic }
            if ["avif", "avis"].contains(brand) { return .avif }
            if brand == "qt  " { return .quicktime }
            return .mp4
        }
        return .unknown
    }
    public static func format(of file: URL) -> MediaFormat {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return .unknown }
        defer { try? handle.close() }
        return format(of: (try? handle.read(upToCount: 32)) ?? Data())
    }
    /// Pixel size and frame count from the header, without decoding pixels.
    public static func header(of file: URL) -> (width: Int, height: Int, frames: Int)? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return header(source)
    }
    static func header(_ source: CGImageSource) -> (width: Int, height: Int, frames: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        return (width, height, CGImageSourceGetCount(source))
    }
}
