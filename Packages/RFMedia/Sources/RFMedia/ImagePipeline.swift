// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import ImageIO
import CoreGraphics

/// The one image loading pipeline: every bubble, viewer and (later) avatar image goes through it.
///
/// - Sources are app-private files or in-message thumbnail bytes, never URLs on the network.
/// - Decoding always downsamples to the requested pixel size with ImageIO thumbnailing and runs
///   off the main thread; the orientation is applied into the pixels.
/// - Before any decode the format must be an allowed image format and the header must stay under
///   the pixel cap (100 megapixels); otherwise the result is nil and the item stays a file.
/// - Decoded images live in a memory cache bounded by cost (48 MB by default), purged on memory
///   warnings and when the app locks. Nothing decoded is written to disk.
/// `NSCache` is thread safe and is the only mutable state, hence the unchecked conformance.
public final class ImagePipeline: @unchecked Sendable {
    public static let shared = ImagePipeline()
    public static let pixelCap = 100_000_000
    private let cache: NSCache<NSString, CachedImage>
    public init(memoryBudget: Int = 48 * 1_048_576) {
        let cache = NSCache<NSString, CachedImage>()
        cache.totalCostLimit = memoryBudget
        self.cache = cache
    }

    /// A downsampled image of a stored file; `maxPixel` is the longest side in pixels.
    public func image(file: URL, maxPixel: Int) async -> CGImage? {
        let key = "f|" + file.path + "|" + String(maxPixel) as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard !Task.isCancelled, MediaSniffer.format(of: file).isImage,
                  let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            return Self.downsample(source, maxPixel: maxPixel)
        }.value
        if let decoded, !Task.isCancelled { cache.setObject(CachedImage(decoded), forKey: key, cost: decoded.bytesPerRow * decoded.height) }
        return decoded
    }

    /// A downsampled image of in-memory bytes (the message's inline thumbnail), cached by `id`.
    public func image(data: Data, id: String, maxPixel: Int) async -> CGImage? {
        let key = "d|" + id + "|" + String(maxPixel) as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard !Task.isCancelled, MediaSniffer.format(of: data).isImage,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            return Self.downsample(source, maxPixel: maxPixel)
        }.value
        if let decoded, !Task.isCancelled { cache.setObject(CachedImage(decoded), forKey: key, cost: decoded.bytesPerRow * decoded.height) }
        return decoded
    }

    /// Drops every decoded image (memory warning, lock, account switch).
    public func purge() { cache.removeAllObjects() }

    static func downsample(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        guard let header = MediaSniffer.header(source), header.width * header.height <= pixelCap else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxPixel, max(header.width, header.height))),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

final class CachedImage: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
