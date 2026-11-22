// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import Synchronization
import RamfluxCore
@testable import AppData

private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("rf-media-\(UUID().uuidString)", isDirectory: true) }
private func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }

@Suite(.timeLimit(.minutes(1))) struct ChatMediaTests {
    let attachment = AttachmentRecord(id: "msg#1", name: "photo.jpg", mime: "image/jpeg", messageID: "msg", index: 1, size: 700_000, availableUntil: 4_000_000_000)

    @Test func importEnablesOncePollsReadsInChunksAndStoresThePlaintextPrivately() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data((0..<700_000).map { UInt8($0 % 253) })
        let polls = Mutex(0)
        let transport = ProxyTransport { request in
            switch request.method {
            case "attachment.enable": #expect(request.body == .object(["from_node": .bool(true)])); return .object(["source": .string("node")])
            case "attachment.import.begin":
                #expect(request.body["message_id"] == .string("msg")); #expect(request.body["index"] == .number(1)); #expect(request.body["operation_id"]?.string?.hasPrefix("import:") == true)
                return .object(["import_id": .string("imp"), "generation": .number(1), "state": .string("pending"), "plaintext_length": .number(700_000)])
            case "attachment.import.status":
                let count = polls.withLock { value in value += 1; return value }
                return .object(["import_id": .string("imp"), "generation": .number(1), "state": .string(count < 2 ? "pending" : "ready"), "accepted_through": .number(0), "plaintext_length": .number(700_000)])
            case "attachment.import.read":
                guard case .unsigned(let offset)? = request.body["offset"] else { Issue.record("offset must be unsigned"); return .null }
                #expect(request.body["max_bytes"] == .number(524_288)); #expect(request.body["generation"] == .unsigned(1))
                let end = min(payload.count, Int(offset) + 524_288)
                return .object(["offset": .unsigned(offset), "bytes": .string(base64URL(payload[Int(offset)..<end])), "eof": .bool(end == payload.count)])
            case "attachment.import.finish": return .object(["import_id": .string("imp"), "state": .string("finished")])
            default: Issue.record("Unexpected \(request.method)"); return .null
            }
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root, pause: { _ in })
        guard case .ready(let url) = await repo.download(account: "a", attachment: attachment) else { Issue.record("Import must finish"); return }
        #expect(try Data(contentsOf: url) == payload)
        #expect(url.path.hasPrefix(root.path)); #expect(!url.lastPathComponent.contains("photo"))
        #expect(await repo.mediaState(account: "a", attachment: attachment) == .ready(url))
        #expect(await repo.download(account: "a", attachment: attachment) == .ready(url))
        #expect(transport.calls.withLock { $0.map(\.method) } == ["attachment.enable", "attachment.import.begin", "attachment.import.status", "attachment.import.status", "attachment.import.read", "attachment.import.read", "attachment.import.finish"])
        #expect(await repo.mediaUsage(account: "a").originals == 700_000)
        await repo.purgeAccountMedia(account: "a")
        #expect(await repo.mediaState(account: "a", attachment: attachment) == nil)
    }

    @Test func refusalsBecomeTypedStatesAndExpiredItemsAreNotRequested() async {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        for (code, expected) in [("attachment_deleted", MediaTransferState.removed), ("not_grantee", .notAvailable), ("expired", .expired)] {
            let transport = ProxyTransport { request in
                if request.method == "attachment.enable" { return .object([:]) }
                throw CoreFailure(code: 9, effect: .none, typedName: code)
            }
            let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root, pause: { _ in })
            #expect(await repo.download(account: "a", attachment: attachment) == expected)
        }
        let silent = ProxyTransport { _ in Issue.record("An expired item must not reach the SDK"); return .null }
        let repo = NativeChatRepository(client: RamfluxClient(transport: silent), updates: NativeUpdateSource(client: RamfluxClient(transport: silent)), mediaRoot: root, pause: { _ in })
        let old = AttachmentRecord(id: "o#0", name: "old.pdf", mime: "application/pdf", messageID: "o", index: 0, availableUntil: 1)
        #expect(await repo.download(account: "a", attachment: old) == .expired)
    }

    @Test func aRepeatedEnableCountsAsEnabled() async {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let transport = ProxyTransport { request in
            if request.method == "attachment.enable" { throw CoreFailure(code: 9, effect: .none, typedName: "duplicate_operation") }
            throw CoreFailure(code: 9, effect: .none, typedName: "not_grantee")
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root, pause: { _ in })
        #expect(await repo.download(account: "a", attachment: attachment) == .notAvailable)
    }

    @Test func sendStreamsPreparesWithTheBlake3DigestThenSendsOneMessage() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data((0..<600_000).map { UInt8($0 % 251) })
        var digest = MediaDigest(); digest.update(bytes)
        let expected = digest.hex()
        let received = Mutex(Data())
        let transport = ProxyTransport { request in
            switch request.method {
            case "attachment.enable": return .object([:])
            case "attachment.prepare.begin":
                #expect(request.body["kind"] == .string("dm")); #expect(request.body["peer"] == .string("c")); #expect(request.body["file_name"] == .string("IMG_1.jpg"))
                #expect(request.body["mime"] == .string("image/jpeg")); #expect(request.body["operation_id"] == .string("send-op:0")); #expect(request.operationID?.rawValue == "send-op:0")
                return .object(["prepare_id": .string("p1"), "generation": .number(1), "max_chunk": .number(524_288), "state": .string("accepting")])
            case "attachment.prepare.chunk":
                guard let text = request.body["data_base64"]?.string, let data = Data(base64Encoded: text) else { Issue.record("chunk must be base64"); return .null }
                #expect(request.body["offset"] == .unsigned(UInt64(received.withLock { $0.count })))
                received.withLock { $0.append(data) }
                return .object(["accepted_through": .number(0)])
            case "attachment.prepare.finish":
                #expect(request.body["plaintext_length"] == .unsigned(600_000)); #expect(request.body["plaintext_digest"] == .string(expected))
                return .object(["state": .string("staged")])
            case "conversation.send":
                #expect(request.body["prepares"] == .array([.object(["prepare_id": .string("p1")])])); #expect(request.body["text"] == .string("Caption"))
                #expect(request.operationID?.rawValue == "send-op")
                return .object(["message_id": .string("event"), "conversation_id": .string("c"), "delivery_state": .string("submitted")])
            default: Issue.record("Unexpected \(request.method)"); return .null
            }
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root, pause: { _ in })
        let outbox = try #require(await repo.mediaOutbox(account: "a"))
        let file = outbox.appendingPathComponent("staged-1")
        try bytes.write(to: file)
        let outside = root.appendingPathComponent("elsewhere"); try bytes.write(to: outside)
        #expect(await repo.enqueueMedia(account: "a", conversation: "c", groupID: nil, caption: "Caption", items: [MediaUpload(file: outside, fileName: "x", mime: "image/jpeg")], operationID: "send-op") == .failure(.invalidInput))
        #expect(await repo.enqueueMedia(account: "a", conversation: "c", groupID: nil, caption: "Caption", items: [MediaUpload(file: file, fileName: "IMG_1.jpg", mime: "image/jpeg")], operationID: "send-op") == .success([SendOutcome(messageID: "event", state: .submitted)]))
        #expect(await repo.outbox(account: "a", conversation: "c").isEmpty)
        #expect(received.withLock { $0 } == bytes)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func sendRefusalsThatARetryCannotFixAreTyped() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let transport = ProxyTransport { request in
            if request.method == "attachment.enable" { return .object([:]) }
            throw CoreFailure(code: 9, effect: .none, typedName: "recipient_limit")
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root, pause: { _ in })
        let outbox = try #require(await repo.mediaOutbox(account: "a"))
        let file = outbox.appendingPathComponent("f"); try Data([1]).write(to: file)
        #expect(await repo.enqueueMedia(account: "a", conversation: "c", groupID: "g", caption: "", items: [MediaUpload(file: file, fileName: "a.bin", mime: "application/octet-stream")], operationID: "op") == .success([]))
        #expect(await repo.outbox(account: "a", conversation: "c").first?.state == .failed(.typedRefusal("recipient_limit")))
        // A definite refusal keeps the staged file until the user discards the entry.
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(await repo.discardOutbox(account: "a", conversation: "c", operationID: "op"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func revokeRetiresGrantsAndErasedRowsDropLocalCopies() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let transport = ProxyTransport { request in
            switch request.method {
            case "attachment.revoke": #expect(request.body == .object(["message_id": .string("msg")])); return .object(["state": .string("relay_erased")])
            case "message.read": return .object(["schema": .string("ramflux.message.read_model.v1"), "conversation_id": .string("c"), "messages": .array([
                .object(["id": .string("gone"), "conversation_id": .string("c"), "state": .string("tombstone"), "kind": .string("tombstone"), "erasure": .object(["scope": .string("everyone")])]),
            ]), "next_before": .null])
            default: Issue.record("Unexpected \(request.method)"); return .null
            }
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root, pause: { _ in })
        let store = MediaStore(base: root)
        try store.prepare(store.conversation("a", "c"))
        for message in ["msg", "gone"] { try Data([1, 2]).write(to: store.file("a", conversation: "c", message: message, index: 0)) }
        guard case .success = await repo.revokeMedia(account: "a", message: "msg") else { Issue.record("Revoke must succeed"); return }
        #expect(store.existing("a", AttachmentRecord(id: "msg#0", name: "", messageID: "msg", conversationID: "c")) == nil)
        _ = await repo.messages(account: "a", conversation: "c", before: nil)
        #expect(store.existing("a", AttachmentRecord(id: "gone#0", name: "", messageID: "gone", conversationID: "c")) == nil)
    }

    @Test func policyNeverDownloadsForStrangersAndCapsGroupsAndCellular() {
        let image = AttachmentRecord(id: "i", name: "", mime: "image/jpeg", size: 3_000_000)
        let file = AttachmentRecord(id: "f", name: "", mime: "application/pdf", size: 20_000_000)
        #expect(!MediaPolicy.autoDownload(image, sender: .untrusted, network: .wifi))
        #expect(MediaPolicy.autoDownload(image, sender: .contact, network: .wifi))
        #expect(MediaPolicy.autoDownload(image, sender: .contact, network: .cellular))
        #expect(!MediaPolicy.autoDownload(image, sender: .contact, network: .constrained))
        #expect(MediaPolicy.autoDownload(file, sender: .contact, network: .wifi))
        #expect(!MediaPolicy.autoDownload(file, sender: .group, network: .wifi))
        #expect(!MediaPolicy.autoDownload(image, sender: .group, network: .cellular))
    }
}
