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
    @Test func sendUsesOnlyConversationIntentAndStableCallerKeyNeverClientRouting() async {
        let transport = ProxyTransport { request in
            #expect(request.method == "conversation.send"); #expect(request.body["conversation_id"] == .string("c")); #expect(request.body["text"] == .string("Hello"))
            #expect(request.body["recipient_device_id"] == nil); #expect(request.operationID?.rawValue == "stable-send")
            return .object(["message_id": .string("m"), "conversation_id": .string("c"), "delivery_state": .string("submitted")])
        }
        let repo = NativeChatRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        #expect(await repo.send(account: "a", conversation: "c", text: "Hello", operationID: "stable-send") == .success(SendOutcome(messageID: "m", state: .submitted)))
    }
}
