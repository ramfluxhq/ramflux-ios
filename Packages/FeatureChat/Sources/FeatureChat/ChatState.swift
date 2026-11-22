// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
import FeatureCards
public enum ComposerIntent: Equatable, Sendable {
    case reply(messageID: String, preview: String)
    case edit(messageID: String, previousDraft: String)
}
public struct PendingMessageDelete: Equatable, Sendable {
    public let messageID: String
    public let scope: MessageDeleteScope
    public init(messageID: String, scope: MessageDeleteScope) { self.messageID = messageID; self.scope = scope }
}
public enum HeldMutation: Equatable, Sendable {
    case revision(operationID: String, messageID: String, text: String, reply: Bool)
    case reaction(operationID: String, messageID: String, token: String, remove: Bool)
    case deletion(operationID: String, messageID: String, scope: MessageDeleteScope)
}
/// The conversation details sheet (members, mute, safety).
public struct ChatDetailsState: Equatable, Sendable {
    public var loading = true
    public var details: ChatDetails?
    public var failure: AppFailure?
    public var muting = false
    /// Bytes of downloaded media of this conversation on this device; nil until measured.
    public var storage: Int64?
    public var confirmClear = false
    public init(loading: Bool = true, details: ChatDetails? = nil, failure: AppFailure? = nil) { self.loading = loading; self.details = details; self.failure = failure }
}
/// A file the user picked, copied by the view layer into the app's temporary directory.
public struct PickedMedia: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case photo, video, file }
    public let url: URL
    public let kind: Kind
    /// The original file name; sent unchanged only for files, never for compressed photos.
    public let name: String
    public init(url: URL, kind: Kind, name: String) { self.url = url; self.kind = kind; self.name = name }
}
/// Picked media staged in the outbox and shown in the send preview; nothing is queued until the
/// user sends. Cancel, removal and leaving the chat erase the staged files.
public struct MediaDraft: Equatable, Sendable {
    public let operationID: String
    public var items: [MediaUpload]
    public var caption: String
    public init(operationID: String, items: [MediaUpload], caption: String = "") { self.operationID = operationID; self.items = items; self.caption = caption }
}
/// What the full-screen viewer or Quick Look shows.
public struct MediaPreview: Equatable, Sendable {
    /// Decided from the stored bytes, never from the declared type.
    public enum Kind: Equatable, Sendable { case image, animated, video, file }
    public let attachmentID: String
    public let file: URL
    public let kind: Kind
    public var isFullScreen: Bool { kind != .file }
    public init(attachmentID: String, file: URL, kind: Kind) { self.attachmentID = attachmentID; self.file = file; self.kind = kind }
}
public struct ChatState: Equatable, Sendable {
    public var isGroup = false
    public var displayTitle = ""
    public var conversationID = ""
    /// The bounded window of read-model rows, newest first.
    public var messages: [MessageRecord] = []
    /// Sends the SDK has not admitted yet, oldest first; drawn below the messages.
    public var outbox: [OutboxEntry] = []
    /// The first unread message; the timeline draws the unread divider above it. Nil while the
    /// SDK supplies no read position (the read model has none today).
    public var unreadAnchorID: String?
    /// True while the read model has older history before the window.
    public var olderAvailable = false
    public var loadingOlder = false
    /// True when the window dropped newer rows while paging back; "Jump to latest" reloads.
    public var detached = false
    public var draft = ""
    /// A peer is typing (from `message.transient`).
    public var peerTyping = false
    public var loading = false
    public var sending = false
    /// The last flush could not reach the account service; queued sends wait for it.
    public var offline = false
    public var failure: AppFailure?
    public var pendingDelete: PendingMessageDelete?
    public var composer: ComposerIntent?
    /// The message whose action menu (reactions, reply, copy, edit, delete) is open.
    public var actionTarget: String?
    public var reactionTarget: String?
    public var reactionRemove = false
    public var held: HeldMutation?
    public var details: ChatDetailsState?
    /// Transfer state per attachment id, only for attachments in the window.
    public var media: [String: MediaTransferState] = [:]
    /// Untrusted senders' thumbnails the user chose to show.
    public var revealed: Set<String> = []
    public var preview: MediaPreview?
    public var attachSheet = false
    /// True after the camera permission is granted; the screen presents the system camera.
    public var cameraActive = false
    /// True while picked media is normalised and staged in the outbox.
    public var staging = false
    public var mediaDraft: MediaDraft?
    public var gallery: ChatGalleryState?
    /// Agent surfaces of the conversation by the id of the message that carried them.
    public var cards: [String: SurfaceCardState] = [:]
    /// The message whose whole album is open.
    public var album: String?
    /// A temporary copy under the original file name while the share sheet is open.
    public var shareFile: URL?
    /// The result of the last "save to Photos"; nil when nothing to report.
    public var photoSaved: Bool?
    public init(messages: [MessageRecord] = [], loading: Bool = false, failure: AppFailure? = nil) { self.messages = messages; self.loading = loading; self.failure = failure }
}
