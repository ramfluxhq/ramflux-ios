// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

enum ReactionToken {
    static func valid(_ token: String) -> Bool {
        guard (1...64).contains(token.utf8.count), token.count == 1 else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            !scalar.properties.isWhitespace && !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

enum MessagePage {
    private static let readModel = "ramflux.message.read_model.v1"
    private static let hiddenKinds: Set<String> = ["edit", "reaction", "receipt", "delete", "typing", "service", "control", "surface", "task", "self_sync"]

    static func records(body: JSONValue, conversation: String) throws -> [MessageRecord] {
        if body["schema"] == .string(readModel) { return try readModelPage(body, conversation) }
        return try legacy(body, conversation)
    }

    static func normalizeIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func legacy(_ body: JSONValue, _ conversation: String) throws -> [MessageRecord] {
        let records = try ProxyGateway.rows(body, "messages").map { row -> MessageRecord in
            let id = try ProxyGateway.text(row, "message_id")
            guard row["conversation_id"] == .string(conversation) else { throw AppFailure.invalidData }
            if row["kind"] == .string("call") {
                return MessageRecord(id: id, sender: "", kind: .callHistory, isOwn: nil, timestamp: ProxyGateway.integer(row["created_at"]))
            }
            let own = row["is_own"]?.bool ?? (row["direction"] == .string("outgoing") ? true : nil)
            if row["deleted"] == .bool(true) { return MessageRecord(id: id, sender: "", kind: .deleted, isOwn: own, timestamp: ProxyGateway.integer(row["created_at"])) }
            let kind: MessageRecord.Kind
            if let text = row["body_utf8"]?.string, text.utf8.count <= 65_536 { kind = .text(text) }
            else { kind = .unsupported(AppDataStrings.text("copy.25c796d9c8f8")) }
            let receipt = receiptText(row["receipts"], own: own)
            let attachments = try attachments(row)
            return MessageRecord(id: id, sender: row["sender_id"]?.string ?? "", kind: kind, isOwn: own, timestamp: ProxyGateway.integer(row["created_at"]), receipt: receipt, attachments: attachments)
        }
        guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }
        return records
    }

    private static func readModelPage(_ body: JSONValue, _ conversation: String) throws -> [MessageRecord] {
        guard body["conversation_id"] == .string(conversation) else { throw AppFailure.invalidData }
        let rows = try ProxyGateway.rows(body, "messages")
        guard rows.count <= 100 else { throw AppFailure.invalidData }
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
            let kindName = row["kind"]?.string ?? ""
            let state = row["state"]?.string
            if hiddenKinds.contains(kindName) { continue }
            let own = row["is_own"]?.bool
            let stamp = displayTime(ProxyGateway.integer(row["hlc"]))
            let sender = row["author"]?["device_id"]?.string ?? row["author"]?["account_anchor"]?.string ?? ""
            if state == "tombstone" || (row["erasure"] != nil && row["erasure"] != .null) {
                records.append(MessageRecord(id: id, sender: "", kind: .deleted, isOwn: own, timestamp: stamp))
                continue
            }
            if kindName == "call" {
                records.append(MessageRecord(id: id, sender: "", kind: .callHistory, isOwn: own, timestamp: stamp))
                continue
            }
            if state == "unsupported" || kindName == "unsupported" {
                records.append(MessageRecord(id: id, sender: sender, kind: .unsupported(AppDataStrings.text("copy.25c796d9c8f8")), isOwn: own, timestamp: stamp))
                continue
            }
            guard kindName == "message" || state == "content" else { continue }
            let rowRevision = ProxyGateway.integer(row["revision"]) ?? 0
            var text = row["text"]?.string ?? row["content"]?["message"]?["text"]?.string
            var edited = row["edited"] == .bool(true) || rowRevision > 0
            if let overlay = overlays[normalizeIdentifier(id)], overlay.revision > rowRevision || text == nil {
                text = overlay.text
                edited = true
            }
            let kind: MessageRecord.Kind
            if let text, text.utf8.count <= 65_536 { kind = .text(text) }
            else { kind = .unsupported(AppDataStrings.text("copy.25c796d9c8f8")) }
            let reply = row["content"]?["message"]?["replyTo"]?["id"]?.string.map(normalizeIdentifier)
            records.append(MessageRecord(id: id, sender: sender, kind: kind, isOwn: own, timestamp: stamp, receipt: receiptText(row["receipts"], own: own), edited: edited, replyTo: reply?.isEmpty == false ? reply : nil, reactions: reactions(row["reactions"])))
        }
        guard Set(records.map { normalizeIdentifier($0.id) }).count == records.count else { throw AppFailure.invalidData }
        let previews = Dictionary(uniqueKeysWithValues: records.compactMap { record -> (String, String)? in
            guard case .text(let text) = record.kind else { return nil }
            return (normalizeIdentifier(record.id), text)
        })
        return records.map { record in
            guard let reply = record.replyTo, let preview = previews[reply] else { return record }
            return MessageRecord(id: record.id, sender: record.sender, kind: record.kind, isOwn: record.isOwn, timestamp: record.timestamp, receipt: record.receipt, attachments: record.attachments, edited: record.edited, replyTo: reply, replyPreview: preview, reactions: record.reactions)
        }
    }

    private static func displayTime(_ raw: Int64?) -> Int64? {
        guard let raw else { return nil }
        let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
        return (0...253402300799).contains(seconds) ? seconds : nil
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

    private static func receiptText(_ value: JSONValue?, own: Bool?) -> String? {
        guard own == true, case .array(let values) = value else { return nil }
        let text = values.compactMap { entry -> String? in
            guard let device = entry["device_id"]?.string, let status = entry["state"]?.string, ["sent", "delivered", "read"].contains(status) else { return nil }
            return AppDataStrings.format("receipt.deviceState", device, AppDataStrings.status(status))
        }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private static func attachments(_ row: JSONValue) throws -> [AttachmentRecord] {
        guard row["attachments"] != nil else { return [] }
        let attachments = try ProxyGateway.rows(row, "attachments").map { item in
            let object = try ProxyGateway.text(item, "object_id")
            return AttachmentRecord(id: object, name: item["name"]?.string ?? object, mime: item["mime"]?.string)
        }
        guard Set(attachments.map(\.id)).count == attachments.count else { throw AppFailure.invalidData }
        return attachments
    }
}
