// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct ConversationsRepositoryTests {
    @Test func directRowsAreNamedByTheSdkClassifiedFromContactsAndFallBackToAShortIdentifier() async {
        let transport = ProxyTransport { request in
            switch request.method {
            case "contact.list": return .object(["contacts": .array([.object(["principal_id": .string("principal-alice"), "display_name": .string("Alice"), "root_commitment": .string("root-alice"), "verified_classification": .string("ai_agent")])])])
            default: return .object(["conversations": .array([
                .object(["id": .string("dm:a"), "peer_principal_id": .string("principal-alice"), "peer_display_name": .string("Alice")]),
                .object(["id": .string("dm:b"), "peer_principal_id": .string("principal-stranger-with-a-long-id")]),
                .object(["id": .string("dm:c"), "title": .string("Named by the SDK"), "peer_principal_id": .string("principal-alice")]),
                .object(["id": .string("group-1"), "group_id": .string("g1")]),
            ])])
            }
        }
        let client = RamfluxClient(transport: transport), updates = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let repository = NativeConversationsRepository(client: client, updates: updates, contacts: NativeContactsRepository(client: client, updates: updates))
        guard case .success(let page) = await repository.page(account: "account", cursor: nil, limit: 50) else { Issue.record("Directory mapping failed"); return }
        #expect(page.rows.map(\.title) == ["Alice", "\u{2066}stranger-w\u{2026}\u{2069}", "Named by the SDK", "group-1"])
        #expect(page.rows.map(\.titleIsIdentifier) == [false, true, false, false])
        #expect(page.rows.map(\.classification) == [.aiAgent, .unknown, .aiAgent, .unknown])
        // A second page within the reuse window does not read contacts again.
        _ = await repository.page(account: "account", cursor: nil, limit: 50)
        #expect(transport.calls.withLock { $0.filter { $0.method == "contact.list" }.count } == 1)
    }
    @Test func sealedDirectoryMappingDoesNotInventProfileOrUnreadAndRejectsDuplicates() async {
        let transport = ProxyTransport { _ in .object(["conversations": .array([
                .object(["id": .string("thread"), "last_activity": .string("9007199254740993")]),
                .object(["id": .string("hidden-thread"), "hidden": .bool(true)]),
                .object(["id": .string("archived-thread"), "archived": .bool(true)]),
            ])]) }
        let client = RamfluxClient(transport: transport), updates = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let repository = NativeConversationsRepository(client: client, updates: updates)
        guard case .success(let page) = await repository.page(account: "account", cursor: nil, limit: 50) else { Issue.record("Directory mapping failed"); return }
        let rows = page.rows; #expect(page.nextCursor == nil)
        #expect(rows.count == 1)
        #expect(rows.first?.id == "thread"); #expect(rows.first?.title == "thread")
        #expect(rows.first?.preview == ""); #expect(rows.first?.unreadCount == nil)
        #expect(rows.first?.lastActivity == 9_007_199_254_740_993)
        #expect(transport.calls.withLock { $0.first?.method } == "conversation.directory")
        #expect(transport.calls.withLock { $0.first?.accountID } == "account")
        let duplicate = ProxyTransport { _ in .object(["conversations": .array([.object(["id": .string("same")]), .object(["id": .string("same")])])]) }
        let invalid = NativeConversationsRepository(client: RamfluxClient(transport: duplicate), updates: updates)
        guard case .failure(.invalidData) = await invalid.page(account: "a", cursor: nil, limit: 50) else { Issue.record("Duplicate IDs must refuse"); return }
        let conflicts: [JSONValue] = [
            .object(["conversations": .array([.object(["id": .string("same")]), .object(["id": .string("same"), "hidden": .bool(true)])])]),
            .object(["conversations": .array([.object(["id": .string("same")]), .object(["id": .string("same"), "archived": .bool(true)])])]),
            .object(["conversations": .array([.object(["id": .string("same"), "hidden": .bool(true)]), .object(["id": .string("same"), "hidden": .bool(true)])])]),
        ]
        for body in conflicts {
            let transport = ProxyTransport { _ in body }
            let repository = NativeConversationsRepository(client: RamfluxClient(transport: transport), updates: updates)
            guard case .failure(.invalidData) = await repository.page(account: "a", cursor: nil, limit: 50) else { Issue.record("Duplicate IDs must refuse before visibility filtering"); return }
        }
    }
    @Test func pagesFollowTheSdkCursorAndCountPendingInboundRequests() async {
        let transport = ProxyTransport { request in
            if request.method == "contact.requests.list" {
                return .object(["requests": .array([
                    .object(["request_id": .string("1"), "direction": .string("inbound"), "state": .string("pending")]),
                    .object(["request_id": .string("2"), "direction": .string("outbound"), "state": .string("pending")]),
                    .object(["request_id": .string("3"), "direction": .string("inbound"), "state": .string("accepted")]),
                ])])
            }
            let after = request.body["cursor"]?.string
            return .object(["conversations": .array([.object(["id": .string(after == nil ? "first" : "second"), "muted": .bool(after != nil), "group_id": after == nil ? .null : .string("g")])]),
                            "next_cursor": after == nil ? .string("c1") : .null])
        }
        let client = RamfluxClient(transport: transport)
        let repository = NativeConversationsRepository(client: client, updates: NativeUpdateSource(client: client))
        guard case .success(let first) = await repository.page(account: "a", cursor: nil, limit: 500) else { Issue.record("first page"); return }
        #expect(first.rows.map(\.id) == ["first"]); #expect(first.nextCursor == "c1"); #expect(first.rows.first?.kind == "person")
        guard case .success(let second) = await repository.page(account: "a", cursor: "c1", limit: 50) else { Issue.record("second page"); return }
        #expect(second.rows.map(\.id) == ["second"]); #expect(second.nextCursor == nil); #expect(second.rows.first?.muted == true); #expect(second.rows.first?.kind == "group")
        let bodies = transport.calls.withLock { $0.map(\.body) }
        #expect(bodies.first?["limit"] == .number(100)); #expect(bodies.last?["cursor"] == .string("c1"))
        #expect(await repository.pendingRequests(account: "a") == .success(1))
    }
}
