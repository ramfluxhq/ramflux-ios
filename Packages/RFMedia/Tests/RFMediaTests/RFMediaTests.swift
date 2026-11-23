// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import RFMedia

private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rf-media-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
/// A JPEG with GPS, EXIF and TIFF metadata and a non-default orientation.
private func photo(width: Int, height: Int, in folder: URL) throws -> URL {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let url = folder.appendingPathComponent("source.jpg")
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2, kCGImagePropertyGPSLongitude: 121.5, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitudeRef: "E"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret place"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Phone"],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

@Suite struct RFMediaTests {
    @Test func normalisedPhotosLoseAllMetadataApplyOrientationAndRespectTheEdgeCap() throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try photo(width: 3_000, height: 2_000, in: folder)
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(try #require(CGImageSourceCreateWithURL(source as CFURL, nil)), 0, nil) as? [CFString: Any]
        #expect(sourceProperties?[kCGImagePropertyGPSDictionary] != nil)
        let result = try ImageNormalizer.normalize(source: source, into: folder, now: Date(timeIntervalSince1970: 0))
        #expect(result.mime == "image/jpeg"); #expect(result.fileName.hasPrefix("IMG_")); #expect(result.fileName.hasSuffix(".jpg"))
        #expect(!result.file.lastPathComponent.contains("source"))
        // Orientation 6 rotates the landscape source into portrait pixels.
        #expect(result.width == 1_707); #expect(result.height == 2_560)
        let output = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
        #expect((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        let bytes = try Data(contentsOf: result.file)
        #expect(bytes.range(of: Data("secret place".utf8)) == nil); #expect(bytes.range(of: Data("GPS".utf8)) == nil)
    }

    @Test func nonImagesAreRefusedByTheirBytesNotTheirName() throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("picture.jpg"); try Data("not an image".utf8).write(to: fake)
        #expect(throws: ImageNormalizer.Failure.notAnImage) { try ImageNormalizer.normalize(source: fake, into: folder) }
        #expect(MediaSniffer.format(of: fake) == .unknown)
        #expect(MediaSniffer.format(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == .png)
        #expect(MediaSniffer.format(of: Data("GIF89a".utf8)) == .gif)
        #expect(MediaSniffer.format(of: Data("RIFF\0\0\0\0WEBP".utf8)) == .webp)
        #expect(MediaSniffer.format(of: Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))) == .heic)
        #expect(MediaSniffer.format(of: Data([0, 0, 0, 0x18] + Array("ftypisom".utf8))) == .mp4)
    }

    @Test func pipelineDownsamplesOffTheMainThreadAndCachesByCost() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try photo(width: 1_200, height: 800, in: folder)
        let pipeline = ImagePipeline(memoryBudget: 8 * 1_048_576)
        let image = try #require(await pipeline.image(file: source, maxPixel: 300))
        #expect(max(image.width, image.height) == 300)
        let again = await pipeline.image(file: source, maxPixel: 300)
        #expect(again === image)
        let text = folder.appendingPathComponent("t.png"); try Data("plain".utf8).write(to: text)
        #expect(await pipeline.image(file: text, maxPixel: 300) == nil)
        pipeline.purge()
        #expect(await pipeline.image(file: source, maxPixel: 300) !== image)
    }
}
