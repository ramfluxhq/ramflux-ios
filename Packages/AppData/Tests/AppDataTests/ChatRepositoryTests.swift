// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
struct ChatRepositoryTests {
    @Test func displayUsesBodyUtf8AndDeletedRowsIgnoreAllResidualIdentityAndContent() async {
        let transport = ProxyTransport { _ in .object(["messages": .array([
            .object(["message_id": .string("m"), "conversation_id": .string("c"), "is_own": .bool(false), "body_utf8": .string("Authenticated display text"), "encrypted_body": .string("DO NOT DISPLAY")]),
            .object(["message_id": .string("deleted"), "conversation_id": .string("c"), "is_own": .bool(true), "deleted": .bool(true), "sender_id": .string("ERASED"), "body_utf8": .string("ERASED")]),
            .object(["id": .string("call"), "message_id": .string("call"), "conversation_id": .string("c"), "kind": .string("call"), "created_at": .number(10), "call": .object([:]), "duration_seconds": .number(5), "missed": .bool(false)]),
        ])]) }
        let client = RamfluxClient(transport: transport), updates = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let repo = NativeChatRepository(client: client, updates: updates)
        guard case .success(let messages) = await repo.messages(account: "a", conversation: "c") else { Issue.record("Mapping failed"); return }
        #expect(messages.first?.kind == .text("Authenticated display text")); #expect(messages.dropFirst().first?.kind == .deleted); #expect(messages.dropFirst().first?.sender == ""); #expect(messages.last?.kind == .callHistory); #expect(messages.last?.isOwn == nil)
    }
    @Test func realLiveRowWithoutOwnershipRemainsDisplayableAndUnknown() async {
        let transport = ProxyTransport { _ in .object(["messages": .array([
            .object(["message_id": .string("peer"), "conversation_id": .string("c"), "sender_id": .string("device"), "body_utf8": .string("Real SDK row"), "direction": .null]),
            .object(["message_id": .string("own"), "conversation_id": .string("c"), "body_utf8": .string("Own copy"), "direction": .string("outgoing")])
        ])]) }
        let client = RamfluxClient(transport: transport)
        let repo = NativeChatRepository(client: client, updates: NativeUpdateSource(client: client))
        guard case .success(let rows) = await repo.messages(account: "a", conversation: "c") else { Issue.record("Real live SDK shape must load"); return }
        #expect(rows.first?.kind == .text("Real SDK row")); #expect(rows.first?.isOwn == nil)
        #expect(rows.last?.isOwn == true)
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
    @Test func messageListRequestsTheReadModelAndProjectsLegacyRowsWhenSelectionIsOff() async {
        let transport = ProxyTransport { request in
            #expect(request.method == "message.list")
            #expect(request.body["read_model"] == .bool(true))
            #expect(request.body["limit"] == .number(100))
            return .object(["messages": .array([.object(["message_id": .string("m"), "conversation_id": .string("c"), "body_utf8": .string("Legacy")])])])
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        guard case .success(let rows) = await repo.messages(account: "a", conversation: "c") else { Issue.record("Legacy page must still load"); return }
        #expect(rows.first?.kind == .text("Legacy"))
    }
    @Test func readModelFoldsEditsReactionsAndRepliesWithoutMutationBubbles() async {
        let target = "AQID"
        let standard = "AQID" // already url-safe; quote uses standard form of the same bytes
        let transport = ProxyTransport { _ in .object([
            "schema": .string("ramflux.message.read_model.v1"),
            "conversation_id": .string("c"),
            "messages": .array([
                .object(["id": .string(target), "conversation_id": .string("c"), "is_own": .bool(true), "state": .string("content"), "kind": .string("message"), "text": .string("Original"), "hlc": .number(1_700_000_000_000), "revision": .number(0), "edited": .bool(false), "reactions": .array([.object(["token": .string("👍"), "count": .number(2)])]), "content": .object(["message": .object(["text": .string("Original")])])]),
                .object(["id": .string("edit-row"), "conversation_id": .string("c"), "is_own": .bool(true), "state": .string("content"), "kind": .string("edit"), "revision": .number(1), "content": .object(["edit": .object(["target": .object(["id": .string(standard)]), "revision": .string("1"), "replacement": .object(["text": .string("Updated")])])])]),
                .object(["id": .string("reply"), "conversation_id": .string("c"), "is_own": .bool(false), "state": .string("content"), "kind": .string("message"), "text": .string("Answer"), "content": .object(["message": .object(["text": .string("Answer"), "replyTo": .object(["id": .string("AQID=")])])])]),
                .object(["id": .string("gone"), "conversation_id": .string("c"), "is_own": .bool(false), "state": .string("tombstone"), "kind": .string("tombstone"), "erasure": .object(["scope": .string("local")]), "text": .string("hidden")]),
                .object(["id": .string("react-row"), "conversation_id": .string("c"), "kind": .string("reaction"), "state": .string("content")]),
            ])
        ]) }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        guard case .success(let rows) = await repo.messages(account: "a", conversation: "c") else { Issue.record("Read model must load"); return }
        #expect(rows.map(\.id) == [target, "reply", "gone"])
        #expect(rows[0].kind == .text("Updated")); #expect(rows[0].edited); #expect(rows[0].reactions == [MessageReaction(token: "👍", count: 2)])
        #expect(rows[0].timestamp == 1_700_000_000)
        #expect(rows[1].replyTo == "AQID"); #expect(rows[1].replyPreview == "Updated")
        #expect(rows[2].kind == .deleted)
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
}
