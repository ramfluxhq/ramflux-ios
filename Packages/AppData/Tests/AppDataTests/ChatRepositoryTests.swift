// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct ChatRepositoryTests {
    @Test func missingOrWrongSchemaIsInvalidData() async {
        let pages: [JSONValue] = [
            .object(["messages": .array([.object(["message_id": .string("m"), "conversation_id": .string("c"), "body_utf8": .string("Authenticated display text"), "direction": .string("outgoing")])])]),
            .object(["schema": .string("ramflux.message.legacy"), "conversation_id": .string("c"), "messages": .array([])]),
        ]
        for page in pages {
            let transport = ProxyTransport { _ in page }
            let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
            guard case .failure(.invalidData) = await repo.messages(account: "a", conversation: "c", before: nil) else { Issue.record("A page without the pinned schema must refuse"); return }
        }
    }
    @Test func malformedCommittedSendProjectionKeepsOriginalAttemptUnknown() async {
        let transport = ProxyTransport { _ in .object(["conversation_id": .string("c"), "delivery_state": .string("submitted")]) }
        let client = RamfluxClient(transport: transport), repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: client))
        #expect(await repo.send(account: "a", conversation: "c", text: "Original", operationID: "stable") == .failure(.outcomeUnknown))
        #expect(await repo.sendState(account: "a", conversation: "c")?.operationID == "stable")
        #expect(await repo.sendState(account: "a", conversation: "c")?.unresolved == true)
    }
    @Test func sendUsesOnlyConversationIntentAndStableCallerKeyNeverClientRouting() async {
        let transport = ProxyTransport { request in
            #expect(request.method == "conversation.send"); #expect(request.body["conversation_id"] == .string("c")); #expect(request.body["text"] == .string("Hello"))
            #expect(request.body["recipient_device_id"] == nil); #expect(request.operationID?.rawValue == "stable-send")
            return .object(["message_id": .string("m"), "conversation_id": .string("c"), "delivery_state": .string("submitted")])
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        #expect(await repo.send(account: "a", conversation: "c", text: "Hello", operationID: "stable-send") == .success(SendOutcome(messageID: "m", state: .submitted)))
    }
    @Test func messageReadRequestsTheReadModelAndRefusesAPageWithoutTheSchema() async {
        let transport = ProxyTransport { request in
            #expect(request.method == "message.read")
            #expect(request.body["read_model"] == .bool(true))
            #expect(request.body["limit"] == .number(50))
            return .object(["messages": .array([.object(["message_id": .string("m"), "conversation_id": .string("c"), "body_utf8": .string("Legacy")])])])
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        guard case .failure(.invalidData) = await repo.messages(account: "a", conversation: "c", before: nil) else { Issue.record("Legacy page must refuse"); return }
    }
    @Test func readModelFoldsEditsReactionsAndRepliesWithoutMutationBubbles() async {
        let target = "AQID"
        let standard = "AQID" // already url-safe; quote uses standard form of the same bytes
        let transport = ProxyTransport { _ in .object([
            "schema": .string("ramflux.message.read_model.v1"),
            "conversation_id": .string("c"),
            "messages": .array([
                .object(["id": .string(target), "conversation_id": .string("c"), "is_own": .bool(true), "state": .string("content"), "kind": .string("message"), "text": .string("Original"), "hlc_ms": .number(1_700_000_000_000), "revision": .number(0), "edited": .bool(false), "reactions": .array([.object(["token": .string("👍"), "count": .number(2)])]), "content": .object(["message": .object(["text": .string("Original")])])]),
                .object(["id": .string("edit-row"), "conversation_id": .string("c"), "is_own": .bool(true), "state": .string("content"), "kind": .string("edit"), "revision": .number(1), "content": .object(["edit": .object(["target": .object(["id": .string(standard)]), "revision": .string("1"), "replacement": .object(["text": .string("Updated")])])])]),
                .object(["id": .string("reply"), "conversation_id": .string("c"), "is_own": .bool(false), "state": .string("content"), "kind": .string("message"), "text": .string("Answer"), "content": .object(["message": .object(["text": .string("Answer"), "replyTo": .object(["id": .string("AQID=")])])])]),
                .object(["id": .string("gone"), "conversation_id": .string("c"), "is_own": .bool(false), "state": .string("tombstone"), "kind": .string("tombstone"), "erasure": .object(["scope": .string("local")]), "text": .string("hidden")]),
                .object(["id": .string("react-row"), "conversation_id": .string("c"), "kind": .string("reaction"), "state": .string("content")]),
            ])
        ]) }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        guard case .success(let page) = await repo.messages(account: "a", conversation: "c", before: nil) else { Issue.record("Read model must load"); return }
        let rows = page.records
        #expect(rows.map(\.id) == [target, "reply", "gone"])
        #expect(rows[0].kind == .text("Updated")); #expect(rows[0].edited); #expect(rows[0].reactions == [MessageReaction(token: "👍", count: 2)])
        #expect(rows[0].timestamp == 1_700_000_000)
        #expect(rows[1].replyTo == "AQID"); #expect(rows[1].replyPreview == "Updated")
        #expect(rows[2].kind == .deleted)
    }
    @Test func aRowThatOnlyHasHlcHasNoTimestamp() async {
        let transport = ProxyTransport { _ in .object([
            "schema": .string("ramflux.message.read_model.v1"),
            "conversation_id": .string("c"),
            "messages": .array([
                .object(["id": .string("clock"), "conversation_id": .string("c"), "is_own": .bool(false), "state": .string("content"), "kind": .string("message"), "text": .string("Clock"), "hlc": .number(1_700_000_000_000)]),
            ]),
        ]) }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        guard case .success(let page) = await repo.messages(account: "a", conversation: "c", before: nil) else { Issue.record("Read model must load"); return }
        let rows = page.records
        #expect(rows.count == 1)
        #expect(rows[0].timestamp == nil)
    }
    @Test func mutationsSendOnlyThePublishedIntentFields() async {
        let transport = ProxyTransport { request in
            switch request.method {
            case "conversation.edit":
                #expect(request.body == .object(["conversation_id": .string("c"), "message_id": .string("m"), "text": .string("Next")]))
            case "conversation.reply":
                #expect(request.body == .object(["conversation_id": .string("c"), "message_id": .string("m"), "text": .string("Back")]))
            case "conversation.react":
                #expect(request.body["token"] == .string("👍")); #expect(request.body["remove"] == nil || request.body["remove"] == .bool(true))
            case "conversation.delete":
                #expect(request.body["scope"] == .string("local") || request.body["scope"] == .string("everyone"))
                #expect(request.body["text"] == nil); #expect(request.body["token"] == nil)
            default: Issue.record("Unexpected method \(request.method)")
            }
            let state = request.method == "conversation.delete" && request.body["scope"] == .string("local") ? "local" : "submitted"
            var body: [String: JSONValue] = ["conversation_id": .string("c"), "message_id": .string("m"), "delivery_state": .string(state)]
            if state == "submitted" { body["target_message_id"] = .string("m"); body["message_id"] = .string("event") }
            return .object(body)
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        func accepted(_ result: RepositoryResult<Void>) -> Bool { if case .success = result { return true }; return false }
        #expect(accepted(await repo.edit(account: "a", conversation: "c", message: "m", text: "Next", operationID: "op")))
        #expect(accepted(await repo.reply(account: "a", conversation: "c", message: "m", text: "Back", operationID: "op")))
        #expect(accepted(await repo.react(account: "a", conversation: "c", message: "m", token: "👍", remove: false, operationID: "op")))
        #expect(accepted(await repo.react(account: "a", conversation: "c", message: "m", token: "👍", remove: true, operationID: "op")))
        #expect(accepted(await repo.delete(account: "a", conversation: "c", message: "m", scope: .local, operationID: "op")))
        #expect(accepted(await repo.delete(account: "a", conversation: "c", message: "m", scope: .everyone, operationID: "op")))
        guard case .failure(let error) = await repo.react(account: "a", conversation: "c", message: "m", token: "not one grapheme", remove: false, operationID: "op") else { Issue.record("Invalid token must be refused"); return }
        #expect(error == .invalidInput)
    }
    @Test func partialDeliveryKeepsTheOriginalMutationKey() async {
        let transport = ProxyTransport { request in
            #expect(request.operationID?.rawValue == "same-key-0123456789abcdef")
            return .object([
                "conversation_id": .string("c"), "message_id": .string("m"), "delivery_state": .string("failed"),
                "deliveries": .array([
                    .object(["target": .string("one"), "state": .string("submitted")]),
                    .object(["target": .string("two"), "state": .string("failed")]),
                ]),
            ])
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        let key = "same-key-0123456789abcdef"
        func refused(_ result: RepositoryResult<Void>) -> AppFailure? { if case .failure(let error) = result { return error }; return nil }
        #expect(refused(await repo.reply(account: "a", conversation: "c", message: "m", text: "Back", operationID: key)) == .outcomeUnknown)
        let pending = await repo.mutationState(account: "a", conversation: "c")
        #expect(pending?.operationID == key); #expect(pending?.unresolved == true); #expect(pending?.key.kind == .reply)
        #expect(refused(await repo.reply(account: "a", conversation: "c", message: "m", text: "Back", operationID: "other-key-0123456789abcdef")) == .outcomeUnknown)
        #expect(transport.calls.withLock { $0.count } == 1)
        #expect(refused(await repo.reply(account: "a", conversation: "c", message: "m", text: "Back", operationID: key)) == .outcomeUnknown)
        #expect(transport.calls.withLock { $0.count } == 2)
        let terminal = ProxyTransport { _ in .object([
            "conversation_id": .string("c"), "message_id": .string("m"), "delivery_state": .string("failed"),
            "deliveries": .array([.object(["target": .string("one"), "state": .string("failed")])]),
        ]) }
        let done = NativeChatRepository(client: RamfluxClient(transport: terminal), updates: NativeUpdateSource(client: RamfluxClient(transport: terminal)))
        #expect(refused(await done.reply(account: "a", conversation: "c", message: "m", text: "Back", operationID: key)) == .failed)
        #expect(await done.mutationState(account: "a", conversation: "c")?.unresolved == false)
    }
}
