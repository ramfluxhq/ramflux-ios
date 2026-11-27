// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CoreGraphics
import ImageIO
import RamfluxCore

/// The object an Image host slot selects, as the SDK resolved it (`attachment`: `retrieval: "object"`). The SDK has
/// already checked conversation membership, the exact digest, erasure and the 8 MiB size before the slot left it.
public struct CardImageSelector: Equatable, Sendable {
    public let objectID: String
    public let manifestDigest: String
    public let transferState: String
    public let size: UInt64
    public let mime: String
}

/// What an Image slot's `attachment` says: an object to read through the object API, or nothing to show.
/// A URL, a path or a data URI is never read from the tree or the slot.
public enum CardImageSource: Equatable, Sendable {
    case object(CardImageSelector)
    case unavailable

    public static func parse(_ attachment: JSONValue?) -> CardImageSource {
        guard let attachment, attachment["retrieval"]?.string == "object",
              let objectID = attachment["object_id"]?.string, !objectID.isEmpty, objectID.utf8.count <= 256,
              let digest = attachment["manifest_digest"]?.string, !digest.isEmpty, digest.utf8.count <= 256,
              let state = attachment["transfer_state"]?.string, !state.isEmpty, state.utf8.count <= 64,
              let size = CardJSON.uint(attachment["size"]), size > 0, size <= UInt64(CardImageLoader.maximumEncodedBytes),
              let mime = attachment["mime"]?.string?.lowercased(), CardImageLoader.allowedMime.contains(mime) else { return .unavailable }
        return .object(CardImageSelector(objectID: objectID, manifestDigest: digest, transferState: state, size: size, mime: mime))
    }
}

/// A decoded image of a card, ready to draw. Immutable.
public final class CardImage: @unchecked Sendable {
    public let cgImage: CGImage
    let decodedBytes: Int
    init(cgImage: CGImage) { self.cgImage = cgImage; decodedBytes = cgImage.bytesPerRow * cgImage.height }
}

public enum CardImageResult: Sendable {
    case image(CardImage)
    /// A refusal, a failed fetch or read, a mismatch or a decode the limits refuse: the card shows "Image unavailable".
    case unavailable
}

/// Reads the bytes of card images through the object API and decodes them within the README limits. Bytes stay in
/// memory (no file, no cache on disk) and are released with the card's session handle or the account's lock.
public actor CardImageLoader {
    static let maximumEncodedBytes = 8 * 1024 * 1024
    static let maximumDimension = 4096
    static let maximumPixels = 4_194_304
    static let maximumDecodedBytesPerSession = 32 * 1024 * 1024
    static let readChunk = 524_288
    static let allowedMime: Set<String> = ["image/png", "image/jpeg"]
    /// How long a fetch that is not `available` is awaited.
    static let fetchDeadline: Duration = .seconds(60)
    static let fetchPoll: Duration = .seconds(2)

    private struct Key: Hashable {
        let account: String
        let surfaceRef: String
        let objectID: String
        let manifestDigest: String
    }
    private struct Session: Hashable {
        let account: String
        let surfaceRef: String
    }

    private let gateway: ProxyGateway
    private var images: [Key: CardImage] = [:]
    private var decodedBytes: [Session: Int] = [:]
    private var inFlight: [Key: Task<CardImageResult, Never>] = [:]
    /// One decode at a time: decoding is the memory peak, so the second waits.
    private var decoding = false
    private var decodeWaiters: [CheckedContinuation<Void, Never>] = []

    init(gateway: ProxyGateway) { self.gateway = gateway }

    /// The image of an Image slot of the card `surfaceRef`; every failure is `.unavailable`.
    public func load(account: String, surfaceRef: String, attachment: JSONValue?) async -> CardImageResult {
        guard case .object(let selector) = CardImageSource.parse(attachment) else { return .unavailable }
        let key = Key(account: account, surfaceRef: surfaceRef, objectID: selector.objectID, manifestDigest: selector.manifestDigest)
        if let image = images[key] { return .image(image) }
        if let task = inFlight[key] { return await task.value }
        let task = Task { await self.fetchAndDecode(key: key, selector: selector) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if case .image(let image) = result {
            images[key] = image
            decodedBytes[Session(account: account, surfaceRef: surfaceRef), default: 0] += image.decodedBytes
        }
        return result
    }

    /// Keeps the images of the cards in the loaded window; the others are released with their sessions.
    public func retain(account: String, surfaceRefs: Set<String>) {
        for key in images.keys where key.account == account && !surfaceRefs.contains(key.surfaceRef) { images[key] = nil }
        for session in decodedBytes.keys where session.account == account && !surfaceRefs.contains(session.surfaceRef) { decodedBytes[session] = nil }
    }

    /// Lock, sign-out or removal: every image of the account leaves memory.
    public func releaseAccount(_ account: String) {
        for key in images.keys where key.account == account { images[key] = nil }
        for session in decodedBytes.keys where session.account == account { decodedBytes[session] = nil }
        for (key, task) in inFlight where key.account == account { task.cancel() }
    }

    // MARK: fetch and read

    private func fetchAndDecode(key: Key, selector: CardImageSelector) async -> CardImageResult {
        guard let data = await bytes(account: key.account, selector: selector) else { return .unavailable }
        guard Self.hasImageMagic(data, mime: selector.mime) else { return .unavailable }
        let used = decodedBytes[Session(account: key.account, surfaceRef: key.surfaceRef), default: 0]
        await acquireDecode()
        defer { releaseDecode() }
        guard !Task.isCancelled, let image = Self.decode(data, budget: Self.maximumDecodedBytesPerSession - used) else { return .unavailable }
        return .image(image)
    }

    private func bytes(account: String, selector: CardImageSelector) async -> Data? {
        // One stable operation id per object: a retry resumes the verified chunks of the earlier attempt.
        let fetchID = "card-image:" + selector.objectID
        guard fetchID.utf8.count <= 256 else { return nil }
        if selector.transferState != "available", !(await fetch(account: account, objectID: selector.objectID, operationID: fetchID)) { return nil }
        let readID = "card-image-read:" + UUID().uuidString
        let body: JSONValue = .object(["object_id": .string(selector.objectID), "operation_id": .string(readID), "protocol_version": .unsigned(1)])
        let begin: JSONValue
        do { begin = try await gateway.call(.objectGetBegin, account: account, body: body) } catch { return nil }
        let data = await read(account: account, begin: begin, selector: selector, operationID: readID)
        // The spool is released whatever the read did; a lost finish only leaves a file the SDK cleans up.
        _ = try? await gateway.call(.objectGetFinish, account: account, body: .object(["operation_id": .string(readID)]))
        return data
    }

    /// `object.fetch` until the object is `available`, at most `fetchDeadline`; a failed transfer ends the wait.
    private func fetch(account: String, objectID: String, operationID: String) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: Self.fetchDeadline)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            let body: JSONValue = .object(["object_id": .string(objectID), "operation_id": .string(operationID)])
            guard let reply = try? await gateway.call(.objectFetch, account: account, body: body) else { return false }
            switch reply["transfer_state"]?.string {
            case "available": return true
            case "failed", nil: return false
            default: try? await Task.sleep(for: Self.fetchPoll)
            }
        }
        return false
    }

    /// Streams the spooled plaintext in bounded slices. The object the SDK opened and the size must be the slot's.
    private func read(account: String, begin: JSONValue, selector: CardImageSelector, operationID: String) async -> Data? {
        guard begin["object_id"]?.string == selector.objectID, let total = ProxyGateway.integer(begin["total_len"]),
              total > 0, total <= Int64(Self.maximumEncodedBytes), UInt64(total) == selector.size else { return nil }
        var data = Data(); data.reserveCapacity(Int(total))
        var offset = 0
        while offset < Int(total) {
            guard !Task.isCancelled else { return nil }
            let length = min(Self.readChunk, Int(total) - offset)
            let body: JSONValue = .object(["operation_id": .string(operationID), "offset": .unsigned(UInt64(offset)), "len": .unsigned(UInt64(length))])
            guard let slice = try? await gateway.call(.objectGetRead, account: account, body: body),
                  let encoded = slice["data_base64"]?.string, let bytes = ChatMediaEngine.base64URL(encoded), bytes.count == length else { return nil }
            data.append(bytes); offset += length
        }
        return data
    }

    // MARK: decode

    private func acquireDecode() async {
        guard decoding else { decoding = true; return }
        await withCheckedContinuation { decodeWaiters.append($0) }
    }

    private func releaseDecode() {
        if decodeWaiters.isEmpty { decoding = false } else { decodeWaiters.removeFirst().resume() }
    }

    static func hasImageMagic(_ data: Data, mime: String) -> Bool {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        switch mime {
        case "image/png": return data.prefix(png.count).elementsEqual(png)
        case "image/jpeg": return data.prefix(3).elementsEqual([0xFF, 0xD8, 0xFF])
        default: return false
        }
    }

    /// Decodes the first frame within the limits: every dimension at most 4096, at most 4,194,304 pixels, and the decoded
    /// bytes within `budget`. The dimensions are read before any pixel is decoded.
    static func decode(_ data: Data, budget: Int) -> CardImage? {
        guard data.count <= maximumEncodedBytes else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) >= 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maximumDimension, height <= maximumDimension, width * height <= maximumPixels,
              width * height * 4 <= budget else { return nil }
        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions), image.width == width, image.height == height else { return nil }
        let result = CardImage(cgImage: image)
        return result.decodedBytes <= budget ? result : nil
    }
}
