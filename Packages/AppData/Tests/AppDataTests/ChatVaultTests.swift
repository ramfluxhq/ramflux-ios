// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import CryptoKit
import Synchronization
import RamfluxCore
@testable import AppData

/// Keys held in memory instead of the keychain (the test host has no keychain entitlement).
final class MemoryVaultKeys: ChatVaultKeys {
    let keys = Mutex<[String: SymmetricKey]>([:])
    func key(account: String, sealedFile: URL) async throws -> SymmetricKey {
        keys.withLock { stored in
            if let key = stored[account], FileManager.default.fileExists(atPath: sealedFile.path) { return key }
            let key = SymmetricKey(size: .bits256); stored[account] = key; return key
        }
    }
    func remove(account: String) async { _ = keys.withLock { $0.removeValue(forKey: account) } }
    var count: Int { keys.withLock { $0.count } }
}

final class RecordingAssertion: MediaBackgroundAssertion {
    let log = Mutex<[String]>([])
    private struct Token: MediaBackgroundToken { let owner: RecordingAssertion; func end() async { owner.log.withLock { $0.append("end") } } }
    func begin(_ name: String) async -> any MediaBackgroundToken { log.withLock { $0.append(name) }; return Token(owner: self) }
}

@Suite(.timeLimit(.minutes(1))) struct ChatVaultTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rf-vault-\(UUID().uuidString)", isDirectory: true)

    private func repository(_ transport: ProxyTransport, keys: MemoryVaultKeys) -> NativeChatRepository {
        NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root.appendingPathComponent("media"),
                             vaultRoot: root.appendingPathComponent("vault"), vaultKeys: keys, pause: { _ in })
    }

    @Test func unsentTextMediaAndDraftsAreSealedRestoredAfterRelaunchAndResumedWithTheirKeys() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryVaultKeys()
        let online = Mutex(false)
        let calls = Mutex<[String]>([])
        let transport = ProxyTransport { request in
            calls.withLock { $0.append(request.method + "@" + (request.operationID?.rawValue ?? "")) }
            guard online.withLock({ $0 }) else { throw CoreFailure(code: 9, effect: .none, typedName: "authority_unavailable") }
            switch request.method {
            case "attachment.enable": return .object([:])
            case "attachment.prepare.begin": return .object(["prepare_id": .string("p"), "generation": .number(1), "state": .string("staged")])
            case "conversation.send": return .object(["message_id": .string("m-" + (request.operationID?.rawValue ?? "")), "conversation_id": request.body["conversation_id"] ?? .null, "delivery_state": .string("submitted")])
            default: Issue.record("Unexpected \(request.method)"); return .null
            }
        }
        let first = repository(transport, keys: keys)
        #expect(await first.enqueue(account: "a", conversation: "c", text: "secret words", operationID: "text-op") == .success([]))
        let outbox = try #require(await first.mediaOutbox(account: "a"))
        let staged = outbox.appendingPathComponent("staged"); try Data("pixels".utf8).write(to: staged)
        #expect(await first.enqueueMedia(account: "a", conversation: "g", groupID: "g", caption: "look", items: [MediaUpload(file: staged, fileName: "IMG_1.jpg", mime: "image/jpeg")], operationID: "media-op") == .success([]))
        await first.saveDraft(account: "a", conversation: "c", text: "half typed")
        await first.sealForLock(account: "a")

        // Nothing readable on disk: one sealed file, no plaintext.
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("vault"), includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let sealed = try Data(contentsOf: try #require(files.first))
        for secret in ["secret words", "half typed", "look", "IMG_1"] { #expect(sealed.range(of: Data(secret.utf8)) == nil) }
        #expect(try root.appendingPathComponent("vault").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        // A new process restores everything after unlock and resumes with the original keys.
        let second = repository(transport, keys: keys)
        #expect(await second.draft(account: "a", conversation: "c") == "half typed")
        let restored = await second.outbox(account: "a", conversation: "g")
        #expect(restored.map(\.operationID) == ["media-op"]); #expect(restored.first?.media.first?.file.lastPathComponent == "staged"); #expect(restored.first?.groupID == "g")
        online.withLock { $0 = true }
        let admitted = await second.resumeAfterUnlock(account: "a")
        #expect(Set(admitted.map(\.messageID)) == ["m-text-op", "m-media-op"])
        #expect(calls.withLock { $0 }.filter { $0.hasPrefix("conversation.send") }.suffix(2).sorted() == ["conversation.send@media-op", "conversation.send@text-op"])
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(await second.outbox(account: "a", conversation: "c").isEmpty)

        // Sent and discarded state leaves the vault; the purge erases the rest with its key.
        await second.saveDraft(account: "a", conversation: "c", text: "")
        await second.sealForLock(account: "a")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("vault").path)) ?? []).isEmpty)
        await second.saveDraft(account: "a", conversation: "c", text: "again")
        await second.sealForLock(account: "a")
        await second.purgeAccount(account: "a")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("vault").path)) ?? []).isEmpty)
        #expect(keys.count == 0)
        #expect(await repository(transport, keys: keys).draft(account: "a", conversation: "c") == "")
    }

    @Test func aMissingKeyOrStagedFileNeverInventsState() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryVaultKeys()
        let transport = ProxyTransport { _ in throw CoreFailure(code: 9, effect: .none, typedName: "authority_unavailable") }
        let first = repository(transport, keys: keys)
        let outbox = try #require(await first.mediaOutbox(account: "a"))
        let staged = outbox.appendingPathComponent("gone"); try Data([1]).write(to: staged)
        _ = await first.enqueueMedia(account: "a", conversation: "c", groupID: nil, caption: "", items: [MediaUpload(file: staged, fileName: "a.bin", mime: "application/octet-stream")], operationID: "op")
        await first.sealForLock(account: "a")
        try FileManager.default.removeItem(at: staged)
        let second = repository(transport, keys: keys)
        #expect(await second.outbox(account: "a", conversation: "c").first?.state == .failed(.localStorage))
        // A failed entry whose files are gone cannot be retried, only discarded.
        _ = await second.retryOutbox(account: "a", conversation: "c", operationID: "op")
        #expect(await second.outbox(account: "a", conversation: "c").first?.state == .failed(.localStorage))
        await keys.remove(account: MediaStore.hash("a"))
        #expect(await repository(transport, keys: keys).outbox(account: "a", conversation: "c").isEmpty)
    }

    @Test func aFailedRevokeIsKeptAndRetriedOnTheNextFlush() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryVaultKeys()
        let online = Mutex(false)
        let revokes = Mutex(0)
        let transport = ProxyTransport { request in
            guard request.method == "attachment.revoke" else { Issue.record("Unexpected \(request.method)"); return .null }
            revokes.withLock { $0 += 1 }
            guard online.withLock({ $0 }) else { throw CoreFailure(code: 9, effect: .none, typedName: "authority_unavailable") }
            return .object(["message_id": .string("msg"), "state": .string("relay_erased")])
        }
        let first = repository(transport, keys: keys)
        guard case .failure = await first.revokeMedia(account: "a", message: "msg") else { Issue.record("Offline revoke must fail"); return }
        await first.sealForLock(account: "a")
        let second = repository(transport, keys: keys)
        online.withLock { $0 = true }
        _ = await second.flushOutbox(account: "a", conversation: "c")
        #expect(revokes.withLock { $0 } == 2)
        _ = await second.flushOutbox(account: "a", conversation: "c")
        #expect(revokes.withLock { $0 } == 2)
    }

    @Test func aResumedPrepareStreamsOnlyBytesTheSDKHasNotAcceptedButHashesAll() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data((0..<1_200_000).map { UInt8($0 % 249) })
        var digest = BLAKE3(); digest.update(bytes)
        let expected = digest.hex()
        let offsets = Mutex<[UInt64]>([])
        let transport = ProxyTransport { request in
            switch request.method {
            case "attachment.enable": return .object([:])
            case "attachment.prepare.begin": return .object(["prepare_id": .string("p"), "generation": .number(1), "state": .string("accepting"), "accepted_through": .number(600_000)])
            case "attachment.prepare.chunk":
                guard case .unsigned(let offset)? = request.body["offset"], let data = request.body["data_base64"]?.string.flatMap({ Data(base64Encoded: $0) }) else { return .null }
                offsets.withLock { $0.append(offset) }
                #expect(data == bytes[Int(offset)..<Int(offset) + data.count])
                return .object([:])
            case "attachment.prepare.finish": #expect(request.body["plaintext_digest"] == .string(expected)); return .object([:])
            case "conversation.send": return .object(["message_id": .string("m"), "conversation_id": .string("c"), "delivery_state": .string("submitted")])
            default: Issue.record("Unexpected \(request.method)"); return .null
            }
        }
        let repo = repository(transport, keys: MemoryVaultKeys())
        let outbox = try #require(await repo.mediaOutbox(account: "a"))
        let file = outbox.appendingPathComponent("big"); try bytes.write(to: file)
        #expect(await repo.enqueueMedia(account: "a", conversation: "c", groupID: nil, caption: "", items: [MediaUpload(file: file, fileName: "a.bin", mime: "application/octet-stream")], operationID: "op") == .success([SendOutcome(messageID: "m", state: .submitted)]))
        #expect(offsets.withLock { $0 } == [600_000, 1_048_576])
    }

    @Test func forwardImportsWhenNeededAndQueuesANewMediaSend() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let methods = Mutex<[String]>([])
        let transport = ProxyTransport { request in
            methods.withLock { $0.append(request.method) }
            switch request.method {
            case "attachment.enable": return .object([:])
            case "attachment.prepare.begin":
                #expect(request.body["file_name"] == .string("report.pdf")); #expect(request.body["peer"] == .string("other"))
                return .object(["prepare_id": .string("p"), "generation": .number(1), "state": .string("staged")])
            case "conversation.send":
                #expect(request.body["text"] == .string("see this")); #expect(request.body["conversation_id"] == .string("other"))
                return .object(["message_id": .string("fwd"), "conversation_id": .string("other"), "delivery_state": .string("submitted")])
            default: Issue.record("Unexpected \(request.method)"); return .null
            }
        }
        let repo = repository(transport, keys: MemoryVaultKeys())
        let store = MediaStore(base: root.appendingPathComponent("media"))
        try store.prepare(store.conversation("a", "c"))
        try Data("pdf".utf8).write(to: store.file("a", conversation: "c", message: "msg", index: 0))
        let attachment = AttachmentRecord(id: "msg#0", name: ".re\u{202E}port.pdf", mime: "application/pdf", messageID: "msg", conversationID: "c", index: 0)
        #expect(await repo.forward(account: "a", text: "see this", attachments: [attachment], to: "other", groupID: nil, operationID: "fwd-op") == .success([SendOutcome(messageID: "fwd", state: .submitted)]))
        #expect(store.existing("a", attachment) != nil)
        #expect(!methods.withLock { $0 }.contains("attachment.import.begin"))

        // Share uses a temporary copy under the sanitised original name, removed afterwards.
        let copy = try #require(await repo.shareCopy(account: "a", file: store.file("a", attachment), name: attachment.name))
        #expect(copy.lastPathComponent == "report.pdf"); #expect(try Data(contentsOf: copy) == Data("pdf".utf8))
        #expect(await repo.shareCopy(account: "a", file: root.appendingPathComponent("elsewhere"), name: "x") == nil)
        await repo.removeShareCopy(account: "a")
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func storageIsMeasuredAndClearedPerConversationAndAccountWithoutTouchingQueuedSends() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = ProxyTransport { _ in throw CoreFailure(code: 9, effect: .none) }
        let repo = repository(transport, keys: MemoryVaultKeys())
        let store = MediaStore(base: root.appendingPathComponent("media"))
        for (conversation, size) in [("c1", 100), ("c2", 50)] {
            try store.prepare(store.conversation("a", conversation))
            try Data(count: size).write(to: store.file("a", conversation: conversation, message: "m-" + conversation, index: 0))
        }
        let outbox = try #require(await repo.mediaOutbox(account: "a"))
        let staged = outbox.appendingPathComponent("queued"); try Data(count: 7).write(to: staged)
        _ = await repo.enqueueMedia(account: "a", conversation: "c1", groupID: nil, caption: "", items: [MediaUpload(file: staged, fileName: "a.bin", mime: "application/octet-stream")], operationID: "op")
        let orphan = outbox.appendingPathComponent("orphan"); try Data(count: 3).write(to: orphan)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: orphan.path)
        let fresh = outbox.appendingPathComponent("fresh"); try Data(count: 3).write(to: fresh)
        #expect(await repo.mediaUsage(account: "a", conversation: "c1") == 100)
        #expect(await repo.mediaUsage(account: "a") == MediaUsage(originals: 150, outbox: 13))
        await repo.purgeConversationMedia(account: "a", conversation: "c1")
        #expect(await repo.mediaUsage(account: "a", conversation: "c1") == 0); #expect(await repo.mediaUsage(account: "a", conversation: "c2") == 50)
        await repo.purgeAccountMedia(account: "a")
        #expect(await repo.mediaUsage(account: "a").originals == 0)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        _ = await repo.resumeAfterUnlock(account: "a")
        #expect(!FileManager.default.fileExists(atPath: orphan.path)); #expect(FileManager.default.fileExists(atPath: fresh.path)); #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func transfersRunUnderABackgroundAssertionThatEndsWithThem() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = ProxyTransport { request in
            switch request.method {
            case "attachment.enable": return .object([:])
            case "attachment.prepare.begin": return .object(["prepare_id": .string("p"), "generation": .number(1), "state": .string("staged")])
            case "conversation.send": return .object(["message_id": .string("m"), "conversation_id": .string("c"), "delivery_state": .string("submitted")])
            default: throw CoreFailure(code: 9, effect: .none, typedName: "not_grantee")
            }
        }
        let assertion = RecordingAssertion()
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: root, background: assertion, pause: { _ in })
        let outbox = try #require(await repo.mediaOutbox(account: "a"))
        let file = outbox.appendingPathComponent("f"); try Data([1]).write(to: file)
        _ = await repo.enqueueMedia(account: "a", conversation: "c", groupID: nil, caption: "", items: [MediaUpload(file: file, fileName: "a.bin", mime: "application/octet-stream")], operationID: "op")
        _ = await repo.download(account: "a", attachment: AttachmentRecord(id: "x#0", name: "", mime: "image/jpeg", messageID: "x", conversationID: "c", availableUntil: 4_000_000_000))
        #expect(assertion.log.withLock { $0 } == ["ramflux.media.upload", "end", "ramflux.media.download", "end"])
    }
}

/// A stand-in for the shared event source's `message.transient` feed.
final class FakeTransients: ChatTransientSource {
    let bodies: [JSONValue]
    init(_ bodies: [JSONValue]) { self.bodies = bodies }
    func transients(account: String) async -> AsyncStream<JSONValue> {
        AsyncStream { continuation in for body in bodies { continuation.yield(body) }; continuation.finish() }
    }
}

@Suite struct ChatTypingTests {
    static func body(conversation: String, author: String, active: Bool, expires: String = "1767258010", group: Bool = false) -> JSONValue {
        var identity: [String: JSONValue] = ["id": .string("aWQ"), "conversationId": .string(conversation), "author": .object(["accountAnchor": .string(author), "deviceId": .string("d"), "deviceEpoch": .string("1")])]
        if group { identity["groupId"] = .string("g") }
        var typing: [String: JSONValue] = ["expiresAt": .string(expires)]
        if active { typing["active"] = .bool(true) }
        return .object(["accountId": .string("a"), "identity": .object(identity), "content": .object(["typing": .object(typing)])])
    }

    @Test func transientTypingBodiesAreParsedAndFilteredByConversation() async {
        #expect(TypingEvent.parse(Self.body(conversation: "c", author: "peer", active: true)) == TypingEvent(conversationID: "c", author: "peer", active: true, expiresAt: 1_767_258_010))
        #expect(TypingEvent.parse(Self.body(conversation: "c", author: "peer", active: false))?.active == false)
        #expect(TypingEvent.parse(Self.body(conversation: "c", author: "peer", active: true, group: true)) == nil)
        #expect(TypingEvent.parse(Self.body(conversation: "c", author: "peer", active: true, expires: "0")) == nil)
        #expect(TypingEvent.parse(.object(["content": .object(["text": .string("x")])])) == nil)
        let source = FakeTransients([Self.body(conversation: "other", author: "x", active: true), Self.body(conversation: "c", author: "peer", active: true), .object([:])])
        let transport = ProxyTransport { _ in .null }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: nil, transients: source, pause: { _ in })
        var events: [TypingEvent] = []
        for await event in await repo.typing(account: "a", conversation: "c") { events.append(event) }
        #expect(events.map(\.author) == ["peer"])
        let silent = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), mediaRoot: nil, pause: { _ in })
        var none = 0
        for await _ in await silent.typing(account: "a", conversation: "c") { none += 1 }
        #expect(none == 0)
    }
}
