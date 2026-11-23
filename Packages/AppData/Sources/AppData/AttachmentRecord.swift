// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
/// A small preview image the sender put into the message (`MediaRef.inline_thumbnail`).
public struct AttachmentThumbnail: Sendable, Equatable {
    public let mime: String
    public let width: Int
    public let height: Int
    public let data: Data
    public init(mime: String, width: Int, height: Int, data: Data) { self.mime = mime; self.width = width; self.height = height; self.data = data }
}
/// One item of `content.message.media[]` as the read model returns it. Key slots, grant ids and
/// read capabilities never reach this record: the SDK strips them before the read model is built.
/// `name` is sender-controlled text: render it only through the untrusted file-name primitive and
/// never use it as a path.
public struct AttachmentRecord: Identifiable, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable, Equatable { case image, animated, video, file }
    public var description: String { "AttachmentRecord(<redacted>)" }
    /// `<message id>#<index>`; stable across reloads.
    public let id: String
    public let messageID: String
    /// The conversation the message belongs to; stored originals are grouped by it so storage
    /// can be shown and cleared per conversation.
    public let conversationID: String
    public let index: Int
    public let name: String
    public let mime: String?
    public let size: Int64?
    public let thumbnail: AttachmentThumbnail?
    /// Unix seconds after which the relay refuses the import (the grant's hard deadline).
    public let availableUntil: Int64?
    public init(id: String, name: String, mime: String? = nil, messageID: String = "", conversationID: String = "", index: Int = 0, size: Int64? = nil, thumbnail: AttachmentThumbnail? = nil, availableUntil: Int64? = nil) {
        self.id = id; self.name = name; self.mime = mime; self.messageID = messageID; self.conversationID = conversationID; self.index = index; self.size = size; self.thumbnail = thumbnail; self.availableUntil = availableUntil
    }
    /// The placeholder kind chosen from the declared type. The bytes decide the renderer after
    /// download; a declared image that is not an image falls back to a file bubble.
    public var kind: Kind {
        guard let mime = mime?.lowercased() else { return .file }
        if ["image/gif", "image/apng"].contains(mime) { return .animated }
        if ["image/jpeg", "image/png", "image/heic", "image/heif", "image/webp", "image/avif"].contains(mime) { return .image }
        if mime.hasPrefix("video/") { return .video }
        return .file
    }
    /// Width over height of the inline thumbnail, clamped to 0.5...2.0; nil without a thumbnail.
    /// The bubble box comes only from this value (or a fixed 4:3 box), so a finished download
    /// never changes the row height.
    public var aspectRatio: Double? {
        guard let thumbnail, thumbnail.width > 0, thumbnail.height > 0 else { return nil }
        return min(2.0, max(0.5, Double(thumbnail.width) / Double(thumbnail.height)))
    }
    public func isExpired(now: Date) -> Bool {
        guard let availableUntil else { return false }
        return Int64(now.timeIntervalSince1970) >= availableUntil
    }
}
