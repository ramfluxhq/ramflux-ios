// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AVFoundation
import CoreGraphics

/// Video for chat (media design 4.3, owner decision O6): sent videos are transcoded on the device
/// to H.264/AAC MP4 with the long edge at most 1,280 px, at most 10 minutes and 200 MB, with no
/// metadata. Received videos are played only after the full download (no streaming); the poster
/// and duration are derived on this device because the message cannot carry them yet (R2).
public enum VideoMedia {
    public static let maxDuration: Double = 600
    public static let maxBytes: Int64 = 200 * 1_048_576
    public enum Failure: Error, Sendable, Equatable { case notAVideo, tooLong, tooLarge, exportFailed }
    public struct Result: Sendable, Equatable {
        public let file: URL
        public let fileName: String
        public let mime: String
        public let duration: Double
    }

    public static func transcode(source: URL, into directory: URL, now: Date = Date()) async throws -> Result {
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { throw Failure.notAVideo }
        guard duration <= maxDuration else { throw Failure.tooLong }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw Failure.exportFailed }
        let file = directory.appendingPathComponent(UUID().uuidString)
        export.metadata = []
        export.metadataItemFilter = .forSharing()
        export.shouldOptimizeForNetworkUse = true
        do { try await export.export(to: file, as: .mp4) } catch { try? FileManager.default.removeItem(at: file); throw Failure.exportFailed }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size > 0 else { try? FileManager.default.removeItem(at: file); throw Failure.exportFailed }
        guard size <= maxBytes else { try? FileManager.default.removeItem(at: file); throw Failure.tooLarge }
        return Result(file: file, fileName: ImageNormalizer.name(now, ext: "mp4").replacingOccurrences(of: "IMG_", with: "VID_"), mime: "video/mp4", duration: duration)
    }

    /// The first frame (orientation applied) and the duration of a stored video, off the main thread.
    public static func poster(file: URL, maxPixel: Int) async -> (image: CGImage, duration: Double)? {
        guard MediaSniffer.format(of: file).isVideo else { return nil }
        let asset = AVURLAsset(url: file)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let image = try? await generator.image(at: .zero).image, let duration = try? await asset.load(.duration).seconds, duration.isFinite else { return nil }
        return (image, duration)
    }
}

/// Animated images (GIF, APNG; animated WebP where ImageIO decodes it) play only when allowed:
/// never with Reduce Motion or Low Power Mode, and only under the frame budget.
public enum AnimatedImage {
    public static let frameBudget = 200_000_000
    public static func shouldAnimate(file: URL, reduceMotion: Bool, lowPower: Bool) -> Bool {
        guard !reduceMotion, !lowPower, let header = MediaSniffer.header(of: file), header.frames > 1 else { return false }
        return header.frames * header.width * header.height <= frameBudget
    }
}
