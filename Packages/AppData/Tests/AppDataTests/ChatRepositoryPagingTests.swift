// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import Synchronization
import RamfluxCore
@testable import AppData

private func repository(_ transport: ProxyTransport) -> NativeChatRepository {
    NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
}
private func row(_ id: String, own: Bool = false, text: String = "Hello", hlc: Double = 1_700_000_000_000, journal: Double = 1, extra: [String: JSONValue] = [:]) -> JSONValue {
    var value: [String: JSONValue] = ["id": .string(id), "conversation_id": .string("c"), "is_own": .bool(own), "state": .string("content"), "kind": .string("message"), "text": .string(text),
                                     "hlc_ms": .number(hlc), "hlc_logical": .number(0), "device_sequence": .string("00000000000000000001"), "journal_sequence": .number(journal),
                                     "author": .object(["account_anchor": .string(own ? "me" : "peer-anchor"), "device_id": .string(own ? "phone" : "peer-phone")])]
    for (key, item) in extra { value[key] = item }
    return .object(value)
}
private func page(_ rows: [JSONValue], before: JSONValue = .null, snapshot: Double = 9) -> JSONValue {
    .object(["schema": .string("ramflux.message.read_model.v1"), "conversation_id": .string("c"), "messages": .array(rows), "next_before": before, "snapshot_sequence": .number(snapshot)])
}

@Suite(.timeLimit(.minutes(1))) struct ChatRepositoryPagingTests {
    @Test func olderPagesPassTheOpaqueCursorUnchangedAndReportTheStart() async {
        let cursor: JSONValue = .object(["hlc_ms": .number(5), "device_sequence": .string("00000000000000000002"), "opaque": .array([.number(1)])])
        let transport = ProxyTransport { request in
            #expect(request.method == "message.read"); #expect(request.body["read_model"] == .bool(true)); #expect(request.body["limit"] == .number(50))
            if let before = request.body["before_order_key"] {
                #expect(before == cursor)
                return page([row("old")])
            }
            return page([row("new", journal: 3)], before: cursor, snapshot: 12)
        }
        let repo = repository(transport)
        guard case .success(let first) = await repo.messages(account: "a", conversation: "c", before: nil) else { Issue.record("First page must load"); return }
        #expect(first.records.map(\.id) == ["new"]); #expect(first.snapshotSequence == 12); #expect(first.nextBefore != nil)
        #expect(first.records[0].journalSequence == 3); #expect(first.records[0].order == MessageOrder(milliseconds: 1_700_000_000_000, logical: 0, sequence: "00000000000000000001"))
        guard case .success(let older) = await repo.messages(account: "a", conversation: "c", before: first.nextBefore) else { Issue.record("Older page must load"); return }
        #expect(older.records.map(\.id) == ["old"]); #expect(older.nextBefore == nil)
    }

    @Test func changeBatchesFollowTheCursorAndKeepTheLatestStateOfEachRow() async {
        let transport = ProxyTransport { request in
            if request.method == "account.status" { return .object(["device_id": .string("device-me")]) }
            #expect(request.body["after_sequence"] == .unsigned(9)); #expect(request.body["read_model"] == nil); #expect(request.body["before_order_key"] == nil)
            return .object(["schema": .string("ramflux.message.read_model.v1"), "conversation_id": .string("c"), "next_after": .number(14), "more": .bool(true), "changes": .array([
                row("m1", text: "First", journal: 10),
                row("svc", journal: 11, extra: ["kind": .string("service")]),
                row("m1", text: "Edited", journal: 12, extra: ["revision": .number(1), "edited": .bool(true)]),
                .object(["id": .string("m2"), "conversation_id": .string("c"), "state": .string("tombstone"), "kind": .string("tombstone"), "erasure": .object(["scope": .string("everyone")]), "journal_sequence": .number(13)]),
            ])])
        }
        guard case .success(let batch) = await repository(transport).changes(account: "a", conversation: "c", after: 9) else { Issue.record("Changes must load"); return }
        #expect(batch.nextAfter == 14); #expect(batch.more)
        #expect(batch.changes.count == 3)
        guard case .hidden("svc") = batch.changes[0], case .row(let edited) = batch.changes[1], case .row(let gone) = batch.changes[2] else { Issue.record("Unexpected change shapes"); return }
        #expect(edited.kind == .text("Edited")); #expect(edited.edited); #expect(gone.kind == .deleted)
    }

    @Test func receiptsBecomeAStructuredDeliveryStateOnlyForOwnMessages() async {
        let receipts: JSONValue = .array([
            .object(["device_id": .string("d1"), "state": .string("delivered")]),
            .object(["device_id": .string("d2"), "state": .string("read")]),
            .object(["device_id": .string("d3"), "state": .string("forged")]),
        ])
        let transport = ProxyTransport { _ in page([row("own", own: true, extra: ["receipts": receipts]), row("theirs", extra: ["receipts": receipts]), row("bare", own: true)]) }
        guard case .success(let result) = await repository(transport).messages(account: "a", conversation: "c", before: nil) else { Issue.record("Page must load"); return }
        #expect(result.records[0].delivery == .read)
        #expect(result.records[0].receipts == [MessageReceipt(device: "d1", state: .delivered), MessageReceipt(device: "d2", state: .read)])
        #expect(result.records[1].delivery == nil); #expect(result.records[1].receipts.isEmpty)
        #expect(result.records[2].delivery == nil)
    }

    @Test func mediaItemsAreParsedFromGeneratedContentWithoutKeyMaterial() async throws {
        let item: JSONValue = .object([
            "fileName": .string("pic\u{202E}gpj.exe"), "mimeType": .string("IMAGE/JPEG"), "size": .string("64"), "objectId": .string("object"),
            "inlineThumbnail": .object(["encodedImage": .string("dGh1bWItYnl0ZXM="), "height": .number(30), "mimeType": .string("image/jpeg"), "width": .number(90)]),
            "largeManifest": .object(["expiresAt": .string("4000000000"), "plaintextLength": .string("64")]),
        ])
        let file: JSONValue = .object(["file_name": .string("notes.pdf"), "mime_type": .string("application/pdf"), "size": .number(2048)])
        let broken: JSONValue = .object(["fileName": .string("no type")])
        let transport = ProxyTransport { _ in page([row("m", text: "", extra: ["content": .object(["message": .object(["text": .string(""), "media": .array([item, file, broken])])])])]) }
        guard case .success(let result) = await repository(transport).messages(account: "a", conversation: "c", before: nil) else { Issue.record("Page must load"); return }
        let media = result.records[0].attachments
        #expect(media.count == 2)
        #expect(media[0].id == "m#0"); #expect(media[0].messageID == "m"); #expect(media[0].index == 0)
        #expect(media[0].mime == "image/jpeg"); #expect(media[0].kind == .image); #expect(media[0].size == 64)
        #expect(media[0].availableUntil == 4_000_000_000); #expect(media[0].thumbnail?.data == Data("thumb-bytes".utf8))
        #expect(media[0].aspectRatio == 2.0)
        #expect(media[1].id == "m#1"); #expect(media[1].kind == .file); #expect(media[1].thumbnail == nil); #expect(media[1].aspectRatio == nil)
        #expect(String(describing: media[0]) == "AttachmentRecord(<redacted>)")
    }

    @Test func outboxKeepsOfflineSendsQueuedInOrderAndRetriesWithTheSameKeys() async {
        let online = Mutex(false)
        let transport = ProxyTransport { request in
            #expect(request.method == "conversation.send")
            guard online.withLock({ $0 }) else { throw AppFailure.offline }
            return .object(["message_id": .string("event-" + (request.operationID?.rawValue ?? "")), "conversation_id": .string("c"), "delivery_state": .string("submitted")])
        }
        let repo = repository(transport)
        #expect(await repo.enqueue(account: "a", conversation: "c", text: "first", operationID: "op-first") == .success([]))
        #expect(await repo.enqueue(account: "a", conversation: "c", text: "second", operationID: "op-second") == .success([]))
        let queued = await repo.outbox(account: "a", conversation: "c")
        #expect(queued.map(\.text) == ["first", "second"]); #expect(queued.allSatisfy { $0.state == .queued })
        // Only the head was attempted while offline; the second waits for its turn.
        #expect(transport.calls.withLock { $0.compactMap(\.operationID?.rawValue) } == ["op-first", "op-first"])
        online.withLock { $0 = true }
        let admitted = await repo.flushOutbox(account: "a", conversation: "c")
        #expect(admitted.map(\.messageID) == ["event-op-first", "event-op-second"])
        #expect(await repo.outbox(account: "a", conversation: "c").isEmpty)
        #expect(transport.calls.withLock { $0.compactMap(\.operationID?.rawValue) } == ["op-first", "op-first", "op-first", "op-second"])
    }

    @Test func aDefiniteFailureIsHeldForExplicitRetryAndDoesNotBlockLaterSends() async {
        let attempts = Mutex(0)
        let transport = ProxyTransport { request in
            let attempt = attempts.withLock { value in value += 1; return value }
            let failed = request.operationID?.rawValue == "op-bad" && attempt == 1
            return .object(["message_id": .string("event"), "conversation_id": .string("c"), "delivery_state": .string(failed ? "failed" : "submitted")])
        }
        let repo = repository(transport)
        _ = await repo.enqueue(account: "a", conversation: "c", text: "bad", operationID: "op-bad")
        guard case .failed = await repo.outbox(account: "a", conversation: "c").first?.state else { Issue.record("A failed delivery must be held"); return }
        _ = await repo.enqueue(account: "a", conversation: "c", text: "good", operationID: "op-good")
        #expect(await repo.outbox(account: "a", conversation: "c").map(\.operationID) == ["op-bad"])
        #expect(await repo.retryOutbox(account: "a", conversation: "c", operationID: "op-bad").count == 1)
        #expect(await repo.outbox(account: "a", conversation: "c").isEmpty)
        #expect(transport.calls.withLock { $0.compactMap(\.operationID?.rawValue) } == ["op-bad", "op-good", "op-bad"])
        #expect(await repo.discardOutbox(account: "a", conversation: "c", operationID: "missing") == false)
    }

    @Test func markReadNamesThisDeviceAsTheReader() async {
        let transport = ProxyTransport { request in
            switch request.method {
            case "account.status": return .object(["device_id": .string("phone-1")])
            case "message.receipt.read":
                #expect(request.body == .object(["conversation_id": .string("c"), "message_id": .string("m9"), "reader_id": .string("phone-1")]))
                return .object(["conversation_id": .string("c"), "read_through_message_id": .string("m9"), "scope": .string("local_projection")])
            default: Issue.record("Unexpected \(request.method)"); return .object([:])
            }
        }
        let repo = repository(transport)
        guard case .success = await repo.markRead(account: "a", conversation: "c", message: "m9") else { Issue.record("Mark read must succeed"); return }
        guard case .success = await repo.markRead(account: "a", conversation: "c", message: "m9") else { Issue.record("Mark read must succeed"); return }
        #expect(transport.calls.withLock { $0.map(\.method) } == ["account.status", "message.receipt.read", "message.receipt.read"])
    }

    @Test func typingFocusesSubmitsAGeneratedTypingRequestAndBlurs() async {
        let transport = ProxyTransport { _ in .null }
        let repo = repository(transport)
        guard case .success = await repo.setTyping(account: "a", conversation: "c", isGroup: false, active: true) else { Issue.record("Typing start must succeed"); return }
        guard case .success = await repo.setTyping(account: "a", conversation: "c", isGroup: false, active: false) else { Issue.record("Typing stop must succeed"); return }
        let calls = transport.calls.withLock { $0 }
        #expect(calls.map(\.method) == ["message.focus", "message.submit", "message.submit", "message.focus"])
        #expect(calls[0].body == .object(["conversation_id": .string("c")]))
        #expect(calls[3].body == .object(["conversation_id": .null]))
        let submit = calls[1].body
        #expect(submit["accountId"] == .string("a")); #expect(submit["send"]?["conversationId"] == .string("c"))
        #expect(submit["send"]?["content"]?["typing"]?["active"] == .bool(true)); #expect(calls[2].body["send"]?["content"]?["typing"]?["active"] == .bool(false))
        let operation = submit["requestId"]?.string ?? ""
        #expect((16...64).contains(operation.utf8.count)); #expect(submit["send"]?["operationId"] == .string(Data(operation.utf8).base64EncodedString()))
    }

    @Test func groupTypingSubmitsWithoutFocus() async {
        let transport = ProxyTransport { _ in .null }
        let repo = repository(transport)
        guard case .success = await repo.setTyping(account: "a", conversation: "g", isGroup: true, active: true) else { Issue.record("Typing start must succeed"); return }
        guard case .success = await repo.setTyping(account: "a", conversation: "g", isGroup: true, active: false) else { Issue.record("Typing stop must succeed"); return }
        #expect(transport.calls.withLock { $0.map(\.method) } == ["message.submit", "message.submit"])
    }

    @Test func detailsReadMuteFromTheDirectoryAndMatchThePeerByRootCommitment() async {
        let transport = ProxyTransport { request in
            switch request.method {
            case "conversation.directory":
                if request.body["cursor"] == nil { return .object(["conversations": .array([.object(["id": .string("other")])]), "next_cursor": .string("k1")]) }
                #expect(request.body["cursor"] == .string("k1"))
                return .object(["conversations": .array([.object(["id": .string("c"), "muted": .bool(true), "mute_until": .number(4_000_000_000)])]), "next_cursor": .null])
            case "contact.list":
                return .object(["contacts": .array([.object(["principal_id": .string("lin"), "display_name": .string("Lin"), "root_commitment": .string("peer-anchor")])])])
            case "conversation.mute":
                #expect(request.body == .object(["conversation_id": .string("c"), "unmute": .bool(true)]))
                return .object(["conversation_id": .string("c"), "mute_until": .null])
            default: Issue.record("Unexpected \(request.method)"); return .object([:])
            }
        }
        let repo = repository(transport)
        #expect(await repo.details(account: "a", conversation: "c", peerAnchor: "peer-anchor") == .success(ChatDetails(muted: true, muteUntil: 4_000_000_000, peerPrincipal: "lin", peerName: "Lin")))
        #expect(await repo.setMuted(account: "a", conversation: "c", muted: false, operationID: "mute-op") == .success(false))
    }

    @Test func draftsStayInMemoryPerConversation() async {
        let repo = repository(ProxyTransport { _ in .null })
        await repo.saveDraft(account: "a", conversation: "c", text: "unsent")
        #expect(await repo.draft(account: "a", conversation: "c") == "unsent")
        #expect(await repo.draft(account: "a", conversation: "other") == "")
        await repo.saveDraft(account: "a", conversation: "c", text: "")
        #expect(await repo.draft(account: "a", conversation: "c") == "")
    }
}
