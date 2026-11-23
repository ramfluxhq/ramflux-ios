// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import RFMedia

@Suite struct VideoMediaTests {
    private func gif(frames: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil))
        for index in 0..<frames {
            let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: Double(index) / Double(frames), green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func animatedImagesPlayOnlyWithoutReduceMotionOrLowPower() throws {
        let animated = try gif(frames: 3), still = try gif(frames: 1)
        defer { try? FileManager.default.removeItem(at: animated); try? FileManager.default.removeItem(at: still) }
        #expect(MediaSniffer.format(of: animated) == .gif)
        #expect(AnimatedImage.shouldAnimate(file: animated, reduceMotion: false, lowPower: false))
        #expect(!AnimatedImage.shouldAnimate(file: animated, reduceMotion: true, lowPower: false))
        #expect(!AnimatedImage.shouldAnimate(file: animated, reduceMotion: false, lowPower: true))
        #expect(!AnimatedImage.shouldAnimate(file: still, reduceMotion: false, lowPower: false))
    }

    @Test func nonVideosAreRefusedForTranscodingAndHaveNoPoster() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = folder.appendingPathComponent("clip.mp4"); try Data("not a video".utf8).write(to: text)
        await #expect(throws: VideoMedia.Failure.notAVideo) { try await VideoMedia.transcode(source: text, into: folder) }
        #expect(await VideoMedia.poster(file: text, maxPixel: 100) == nil)
    }
}
