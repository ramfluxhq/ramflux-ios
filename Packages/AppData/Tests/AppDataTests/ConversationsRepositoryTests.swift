// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
struct ConversationsRepositoryTests {
    @Test func sealedDirectoryMappingDoesNotInventProfileOrUnreadAndRejectsDuplicates() async {
        let transport = ProxyTransport { _ in .object(["conversations": .array([.object(["conversation_id": .string("thread"), "last_activity_at": .string("9007199254740993")])])]) }
        let client = RamfluxClient(transport: transport), updates = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let repository = NativeConversationsRepository(client: client, updates: updates)
        guard case .success(let rows) = await repository.list(account: "account") else { Issue.record("Directory mapping failed"); return }
        #expect(rows.first?.id == "thread"); #expect(rows.first?.title == "thread")
        #expect(rows.first?.preview == ""); #expect(rows.first?.unreadCount == nil)
        #expect(rows.first?.lastActivity == 9_007_199_254_740_993)
        #expect(transport.calls.withLock { $0.first?.accountID } == "account")
        let duplicate = ProxyTransport { _ in .object(["conversations": .array([.object(["conversation_id": .string("same")]), .object(["conversation_id": .string("same")])])]) }
        let invalid = NativeConversationsRepository(client: RamfluxClient(transport: duplicate), updates: updates)
        guard case .failure(.invalidData) = await invalid.list(account: "a") else { Issue.record("Duplicate IDs must refuse"); return }
    }
}
