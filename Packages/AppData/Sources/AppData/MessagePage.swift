// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RFLocalization
import RamfluxCore

enum ReactionToken {
    static func valid(_ token: String) -> Bool {
        guard (1...64).contains(token.utf8.count), token.count == 1 else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            !scalar.properties.isWhitespace && !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

/// The opaque `next_before` identity of the read model. It is passed back unchanged as
/// `before_order_key`; the client never builds or inspects it.
public struct MessageCursor: Sendable, Equatable {
    let value: JSONValue
}

/// One page of the read model, newest first.
public struct MessageWindowPage: Sendable, Equatable {
    public let records: [MessageRecord]
    /// Cursor for the next older page; nil when the beginning of history was reached.
    public let nextBefore: MessageCursor?
    /// The journal head the page was read at; changes are followed from it.
    public let snapshotSequence: UInt64?
    public init(records: [MessageRecord], nextBefore: MessageCursor? = nil, snapshotSequence: UInt64? = nil) { self.records = records; self.nextBefore = nextBefore; self.snapshotSequence = snapshotSequence }
}

/// One change batch of the read model: each changed row in its current state, oldest change first.
public struct MessageChangeBatch: Sendable, Equatable {
    public enum Change: Sendable, Equatable {
        /// A displayable row in its current state (content, tombstone, unsupported, call).
        case row(MessageRecord)
        /// A row this client does not display (service, control, surface, task, self sync).
        case hidden(String)
    }
    public let changes: [Change]
    public let nextAfter: UInt64
    public let more: Bool
    public init(changes: [Change], nextAfter: UInt64, more: Bool) { self.changes = changes; self.nextAfter = nextAfter; self.more = more }
}

enum MessagePage {
    static let readModel = "ramflux.message.read_model.v1"
    private static let hiddenKinds: Set<String> = ["edit", "reaction", "receipt", "delete", "typing", "service", "control", "surface", "task", "self_sync"]
    static let maxAttachments = 16

    static func records(body: JSONValue, conversation: String) throws -> [MessageRecord] { try page(body: body, conversation: conversation).records }

    static func page(body: JSONValue, conversation: String, ownDevice: String? = nil) throws -> MessageWindowPage {
        guard body["schema"] == .string(readModel), body["conversation_id"] == .string(conversation) else { throw AppFailure.invalidData }
        let rows = try ProxyGateway.rows(body, "messages")
        guard rows.count <= 100 else { throw AppFailure.invalidData }
        let records = try fold(rows, conversation, ownDevice: ownDevice)
        let before: MessageCursor?
        switch body["next_before"] {
        case nil, .null?: before = nil
        case .object(let value)?: before = MessageCursor(value: .object(value))
        default: throw AppFailure.invalidData
        }
        return MessageWindowPage(records: records, nextBefore: before, snapshotSequence: unsigned(body["snapshot_sequence"]))
    }

    static func changes(body: JSONValue, conversation: String, ownDevice: String? = nil) throws -> MessageChangeBatch {
        guard body["schema"] == .string(readModel), body["conversation_id"] == .string(conversation) else { throw AppFailure.invalidData }
        let rows = try ProxyGateway.rows(body, "changes")
        guard rows.count <= 100, let next = unsigned(body["next_after"]), let more = body["more"]?.bool else { throw AppFailure.invalidData }
        var changes: [MessageChangeBatch.Change] = []
        var seen = Set<String>()
        for row in rows {
            guard row["conversation_id"] == .string(conversation), let id = row["id"]?.string, !id.isEmpty, id.utf8.count <= 256 else { throw AppFailure.invalidData }
            // A later change of the same row in one batch replaces the earlier one.
            if !seen.insert(normalizeIdentifier(id)).inserted { changes.removeAll { change in
                switch change { case .row(let record): normalizeIdentifier(record.id) == normalizeIdentifier(id); case .hidden(let hidden): normalizeIdentifier(hidden) == normalizeIdentifier(id) }
            } }
            if let record = try record(row, conversation, overlays: [:], ownDevice: ownDevice) { changes.append(.row(record)) } else { changes.append(.hidden(id)) }
        }
        return MessageChangeBatch(changes: changes, nextAfter: next, more: more)
    }

    static func normalizeIdentifier(_ value: String) -> String { MessageIdentifier.normalized(value) }

    private static func fold(_ rows: [JSONValue], _ conversation: String, ownDevice: String?) throws -> [MessageRecord] {
        // The unified read model folds edits into their target; legacy edit rows are still
        // applied so an older store never shows a stale body.
        var overlays: [String: (revision: Int64, text: String)] = [:]
        for row in rows where row["kind"] == .string("edit") {
            guard let edit = row["content"]?["edit"], let raw = edit["target"]?["id"]?.string, let text = edit["replacement"]?["text"]?.string, text.utf8.count <= 65_536 else { continue }
            let target = normalizeIdentifier(raw)
            guard !target.isEmpty else { continue }
            let revision = ProxyGateway.integer(edit["revision"]) ?? ProxyGateway.integer(row["revision"]) ?? 0
            if let current = overlays[target], current.revision > revision { continue }
            overlays[target] = (revision, text)
        }
        var records: [MessageRecord] = []
        for row in rows {
            guard row["conversation_id"] == .string(conversation) else { throw AppFailure.invalidData }
            guard let id = row["id"]?.string, !id.isEmpty, id.utf8.count <= 256 else { throw AppFailure.invalidData }
            if let record = try record(row, conversation, overlays: overlays, ownDevice: ownDevice) { records.append(record) }
        }
        guard Set(records.map { normalizeIdentifier($0.id) }).count == records.count else { throw AppFailure.invalidData }
        return resolveReplies(records)
    }

    /// Fills reply previews from rows of the same window. A quoted message outside the window
    /// keeps only its reference.
    static func resolveReplies(_ records: [MessageRecord]) -> [MessageRecord] {
        var previews: [String: String] = [:]
        for record in records { if case .text(let text) = record.kind { previews[normalizeIdentifier(record.id)] = text } }
        return records.map { record in
            guard let reply = record.replyTo else { return record }
            return record.withReplyPreview(previews[reply] ?? record.replyPreview)
        }
    }

    /// Whether a row is this device's own message. The SDK's `is_own` is authoritative when true; a row
    /// authored by this device counts as own as well, because the SDK at 3dafe1f8 stores a message sent
    /// with `conversation.reply` with `is_own: false` on the sending device.
    static func ownership(_ row: JSONValue, ownDevice: String?) -> Bool? {
        let flag = row["is_own"]?.bool
        if flag == true { return true }
        if let ownDevice, !ownDevice.isEmpty, row["author"]?["device_id"]?.string == ownDevice { return true }
        return flag
    }

    private static func record(_ row: JSONValue, _ conversation: String, overlays: [String: (revision: Int64, text: String)], ownDevice: String?) throws -> MessageRecord? {
        guard let id = row["id"]?.string else { throw AppFailure.invalidData }
        let kindName = row["kind"]?.string ?? ""
        let state = row["state"]?.string
        if hiddenKinds.contains(kindName) { return nil }
        let own = ownership(row, ownDevice: ownDevice)
        let stamp = displayTime(ProxyGateway.integer(row["hlc_ms"]))
        let sender = row["author"]?["device_id"]?.string ?? row["author"]?["account_anchor"]?.string ?? ""
        let anchor = row["author"]?["account_anchor"]?.string
        let order = ProxyGateway.integer(row["hlc_ms"]).map { MessageOrder(milliseconds: $0, logical: ProxyGateway.integer(row["hlc_logical"]) ?? 0, sequence: row["device_sequence"]?.string ?? "") }
        let journal = unsigned(row["journal_sequence"])
        if state == "tombstone" || (row["erasure"] != nil && row["erasure"] != .null) {
            return MessageRecord(id: id, sender: "", kind: .deleted, isOwn: own, timestamp: stamp, authorAnchor: anchor, order: order, journalSequence: journal)
        }
        if kindName == "call" {
            return MessageRecord(id: id, sender: "", kind: .callHistory, isOwn: own, timestamp: stamp, authorAnchor: anchor, order: order, journalSequence: journal)
        }
        if state == "unsupported" || kindName == "unsupported" {
            return MessageRecord(id: id, sender: sender, kind: .unsupported(AppDataStrings.text("chat.message.unsupported")), isOwn: own, timestamp: stamp, authorAnchor: anchor, order: order, journalSequence: journal)
        }
        guard kindName == "message" || state == "content" else { return nil }
        let rowRevision = ProxyGateway.integer(row["revision"]) ?? 0
        let message = row["content"]?["message"]
        var text = row["text"]?.string ?? message?["text"]?.string
        var edited = row["edited"] == .bool(true) || rowRevision > 0
        var revision = rowRevision
        if let overlay = overlays[normalizeIdentifier(id)], overlay.revision > rowRevision || text == nil {
            text = overlay.text
            edited = true
            revision = max(revision, overlay.revision)
        }
        let attachments = media(message, messageID: id, conversation: conversation)
        let kind: MessageRecord.Kind
        if let text, text.utf8.count <= 65_536 { kind = .text(text) }
        else { kind = .unsupported(AppDataStrings.text("chat.message.unsupported")) }
        let reply = (message?["replyTo"] ?? message?["reply_to"])?["id"]?.string.map(normalizeIdentifier)
        let receipts = own == true ? receiptRows(row["receipts"]) : []
        return MessageRecord(id: id, sender: sender, kind: kind, isOwn: own, timestamp: stamp, delivery: own == true ? receipts.map(\.state).max() : nil, receipts: receipts,
                             attachments: attachments, edited: edited, replyTo: reply?.isEmpty == false ? reply : nil, reactions: reactions(row["reactions"]),
                             authorAnchor: anchor, order: order, journalSequence: journal, revision: revision)
    }

    /// Parses `content.message.media[]`. Generated content uses protobuf JSON (camelCase); the
    /// snake_case spelling is accepted too. Items that fail validation are skipped, never guessed.
    static func media(_ message: JSONValue?, messageID: String, conversation: String = "") -> [AttachmentRecord] {
        guard case .array(let items)? = message?["media"], items.count <= maxAttachments else { return [] }
        return items.enumerated().compactMap { index, item in
            func field(_ camel: String, _ snake: String) -> JSONValue? { item[camel] ?? item[snake] }
            guard let mime = field("mimeType", "mime_type")?.string, (1...256).contains(mime.utf8.count) else { return nil }
            let rawName = field("fileName", "file_name")?.string ?? ""
            let name = rawName.utf8.count <= 256 ? rawName : ""
            let size = ProxyGateway.integer(field("size", "size")).flatMap { $0 >= 0 ? $0 : nil }
            let manifest = field("largeManifest", "large_manifest")
            let expires = ProxyGateway.integer(manifest?["expiresAt"] ?? manifest?["expires_at"]).flatMap { $0 > 0 ? $0 : nil }
            let length = ProxyGateway.integer(manifest?["plaintextLength"] ?? manifest?["plaintext_length"])
            return AttachmentRecord(id: messageID + "#" + String(index), name: name, mime: mime.lowercased(), messageID: messageID, conversationID: conversation, index: index,
                                    size: size ?? length, thumbnail: thumbnail(field("inlineThumbnail", "inline_thumbnail")), availableUntil: expires)
        }
    }

    private static func thumbnail(_ value: JSONValue?) -> AttachmentThumbnail? {
        guard let value, let mime = (value["mimeType"] ?? value["mime_type"])?.string, mime.hasPrefix("image/"),
              let width = ProxyGateway.integer(value["width"]), let height = ProxyGateway.integer(value["height"]),
              (1...4096).contains(width), (1...4096).contains(height),
              let encoded = (value["encodedImage"] ?? value["encoded_image"])?.string, encoded.utf8.count <= 32_768,
              let data = Data(base64Encoded: encoded), !data.isEmpty else { return nil }
        return AttachmentThumbnail(mime: mime, width: Int(width), height: Int(height), data: data)
    }

    private static func displayTime(_ raw: Int64?) -> Int64? {
        guard let raw else { return nil }
        let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
        return (0...253402300799).contains(seconds) ? seconds : nil
    }

    static func unsigned(_ value: JSONValue?) -> UInt64? {
        switch value {
        case .unsigned(let number)?: number
        case .number(let number)?: number >= 0 ? UInt64(exactly: number) : nil
        case .string(let text)?: UInt64(text)
        default: nil
        }
    }

    private static func reactions(_ value: JSONValue?) -> [MessageReaction] {
        guard case .array(let values) = value, values.count <= 64 else { return [] }
        var seen = Set<String>()
        return values.compactMap { entry in
            guard let token = entry["token"]?.string, ReactionToken.valid(token), seen.insert(token).inserted,
                  let count = ProxyGateway.integer(entry["count"]), (1...10_000).contains(count) else { return nil }
            return MessageReaction(token: token, count: Int(count))
        }
    }

    /// Structured receipts of an own message; the UI folds them into ticks.
    static func receiptRows(_ value: JSONValue?) -> [MessageReceipt] {
        guard case .array(let values) = value, values.count <= 1024 else { return [] }
        return values.compactMap { entry in
            guard let device = entry["device_id"]?.string, !device.isEmpty, device.utf8.count <= 256 else { return nil }
            switch entry["state"]?.string {
            case "sent": return MessageReceipt(device: device, state: .sent)
            case "delivered": return MessageReceipt(device: device, state: .delivered)
            case "read": return MessageReceipt(device: device, state: .read)
            default: return nil
            }
        }
    }
}
