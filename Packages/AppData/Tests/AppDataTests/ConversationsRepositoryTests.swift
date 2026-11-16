// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
struct ConversationsRepositoryTests {
    @Test func sealedDirectoryMappingDoesNotInventProfileOrUnreadAndRejectsDuplicates() async {
        let transport = ProxyTransport { _ in .object(["conversations": .array([
                .object(["id": .string("thread"), "last_activity": .string("9007199254740993")]),
                .object(["id": .string("hidden-thread"), "hidden": .bool(true)]),
                .object(["id": .string("archived-thread"), "archived": .bool(true)]),
            ])]) }
        let client = RamfluxClient(transport: transport), updates = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let repository = NativeConversationsRepository(client: client, updates: updates)
        guard case .success(let rows) = await repository.list(account: "account") else { Issue.record("Directory mapping failed"); return }
        #expect(rows.count == 1)
        #expect(rows.first?.id == "thread"); #expect(rows.first?.title == "thread")
        #expect(rows.first?.preview == ""); #expect(rows.first?.unreadCount == nil)
        #expect(rows.first?.lastActivity == 9_007_199_254_740_993)
        #expect(transport.calls.withLock { $0.first?.method } == "conversation.directory")
        #expect(transport.calls.withLock { $0.first?.accountID } == "account")
        let duplicate = ProxyTransport { _ in .object(["conversations": .array([.object(["id": .string("same")]), .object(["id": .string("same")])])]) }
        let invalid = NativeConversationsRepository(client: RamfluxClient(transport: duplicate), updates: updates)
        guard case .failure(.invalidData) = await invalid.list(account: "a") else { Issue.record("Duplicate IDs must refuse"); return }
    }
}
