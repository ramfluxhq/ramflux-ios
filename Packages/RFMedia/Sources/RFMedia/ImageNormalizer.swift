// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Turns a picked photo into the file that is sent (media design 4.1): orientation applied into
/// the pixels, long edge at most 2,560 px, JPEG at quality 0.82 (PNG stays PNG when it has
/// alpha), and no metadata at all: no EXIF, GPS, XMP, maker notes or original file name.
public enum ImageNormalizer {
    public static let maxEdge = 2_560
    public static let quality = 0.82
    public static let maxSourceBytes: Int64 = 50 * 1_048_576

    public struct Result: Sendable, Equatable {
        public let file: URL
        public let fileName: String
        public let mime: String
        public let width: Int
        public let height: Int
    }
    public enum Failure: Error, Sendable, Equatable { case notAnImage, tooLarge, encodeFailed }

    /// Writes the normalised image into `directory` under a random name.
    public static func normalize(source: URL, into directory: URL, now: Date = Date()) throws -> Result {
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size <= maxSourceBytes else { throw Failure.tooLarge }
        guard MediaSniffer.format(of: source).isImage,
              let input = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw Failure.notAnImage }
        guard let header = MediaSniffer.header(input) else { throw Failure.notAnImage }
        guard header.width * header.height <= ImagePipeline.pixelCap else { throw Failure.tooLarge }
        guard let image = ImagePipeline.downsample(input, maxPixel: maxEdge) else { throw Failure.notAnImage }
        let alpha: Bool = switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: false; default: MediaSniffer.format(of: source) == .png }
        let type: UTType = alpha ? .png : .jpeg
        let file = directory.appendingPathComponent(UUID().uuidString)
        guard let output = CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil) else { throw Failure.encodeFailed }
        // Only pixel data and quality: no properties dictionary carries metadata across.
        CGImageDestinationAddImage(output, image, alpha ? nil : [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { try? FileManager.default.removeItem(at: file); throw Failure.encodeFailed }
        return Result(file: file, fileName: name(now, ext: alpha ? "png" : "jpg"), mime: alpha ? "image/png" : "image/jpeg", width: image.width, height: image.height)
    }

    /// `IMG_<local timestamp>.<ext>`, generated on this device.
    static func name(_ date: Date, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "IMG_" + formatter.string(from: date) + "." + ext
    }
}
