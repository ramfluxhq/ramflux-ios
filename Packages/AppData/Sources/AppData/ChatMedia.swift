// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// Where one attachment stands on this device. The SDK reports no byte progress today, so a
/// running import is indeterminate.
public enum MediaTransferState: Sendable, Equatable {
    /// Not on this device; a tap downloads it.
    case idle
    /// From a stranger or message request: nothing is downloaded or decoded until the user asks.
    case blockedByPolicy
    case downloading
    /// The decrypted original in the private media store.
    case ready(URL)
    /// The import failed; `retryable` is false for refusals a retry cannot fix.
    case failed(AppFailure, retryable: Bool)
    /// The relay window (24 hours after the sender began the upload) has passed.
    case expired
    /// The sender erased it (`attachment_deleted`).
    case removed
    /// This device holds no key for it (`not_grantee`), for example a device paired later.
    case notAvailable
}

/// A normalised file in the account's media outbox, ready to stream into `attachment.prepare`.
public struct MediaUpload: Sendable, Equatable, CustomStringConvertible {
    public var description: String { "MediaUpload(<redacted>)" }
    public let file: URL
    /// The name the recipient sees: generated for compressed images, the original for files.
    public let fileName: String
    public let mime: String
    public init(file: URL, fileName: String, mime: String) { self.file = file; self.fileName = fileName; self.mime = mime }
}

/// Bytes this device holds in its private media store.
public struct MediaUsage: Sendable, Equatable {
    public let originals: Int64
    public let outbox: Int64
    public init(originals: Int64, outbox: Int64) { self.originals = originals; self.outbox = outbox }
}

/// Auto-download decision (media design 6.3). Untrusted senders never download or decode
/// anything without a tap; groups and cellular use smaller caps.
public enum MediaPolicy {
    public enum Sender: Sendable { case contact, group, untrusted }
    public enum Network: Sendable { case wifi, cellular, constrained }
    public static func autoDownload(_ attachment: AttachmentRecord, sender: Sender, network: Network) -> Bool {
        guard sender != .untrusted else { return false }
        let size = attachment.size ?? Int64.max
        let megabyte: Int64 = 1_048_576
        switch (sender, network, attachment.kind) {
        case (.contact, .wifi, .image), (.contact, .wifi, .animated): return true
        case (.contact, .wifi, .video): return size <= 50 * megabyte
        case (.contact, .wifi, .file): return size <= 25 * megabyte
        case (.contact, .cellular, .image), (.contact, .cellular, .animated), (.contact, .cellular, .file): return size <= 5 * megabyte
        case (.contact, .constrained, .image): return size <= 2 * megabyte
        case (.group, .wifi, .image), (.group, .wifi, .animated), (.group, .wifi, .file): return size <= 10 * megabyte
        case (.group, .cellular, .image): return size <= 2 * megabyte
        default: return false
        }
    }
}

/// Maps the SDK's attachment refusal codes (`attachment_send/codes.rs`) to user states.
enum MediaRefusal {
    static let known: Set<String> = ["path_refused", "file_too_large", "manifest_too_large", "stream_closed", "stream_offset", "digest_mismatch", "quota_exceeded", "disk_full",
                                     "peer_upgrade_required", "recipient_limit", "authority_unavailable", "recipient_empty", "not_grantee", "layout_invalid", "seal_failed",
                                     "upload_rejected", "expired", "stale_generation", "not_owner", "not_ready", "cancelled", "duplicate_operation", "attachment_deleted",
                                     "retirement_pending", "large_attachments"]
    static func state(_ code: String?, failure: AppFailure) -> MediaTransferState {
        switch code {
        case "expired"?: .expired
        case "attachment_deleted"?: .removed
        case "not_grantee"?: .notAvailable
        case "disk_full"?, "quota_exceeded"?: .failed(.typedRefusal(code ?? ""), retryable: false)
        case "authority_unavailable"?, "not_ready"?, "stream_closed"?, "cancelled"?: .failed(.offline, retryable: true)
        default: .failed(failure, retryable: failure.canRetry)
        }
    }
    /// Send-side refusals that a retry cannot fix get their own typed failure.
    static func sendFailure(_ code: String?, failure: AppFailure) -> AppFailure {
        switch code {
        case "peer_upgrade_required"?, "recipient_limit"?, "file_too_large"?, "disk_full"?, "quota_exceeded"?: .typedRefusal(code ?? "")
        case "authority_unavailable"?: .offline
        default: failure
        }
    }
}
