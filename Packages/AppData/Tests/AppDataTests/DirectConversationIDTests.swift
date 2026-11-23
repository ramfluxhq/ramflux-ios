// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData

/// Expected values were produced by the reference `blake3` 1.8.7 crate and the SDK's `dm_scope::derive` rule;
/// the hash's own vectors are in `BLAKE3Tests`.
struct DirectConversationIDTests {
    @Test func directConversationIdIsTheSdkDmScopeInEitherOrder() {
        let a = String(repeating: "ERER", count: 10) + "ERE", b = String(repeating: "IiIi", count: 10) + "IiI"
        #expect(DirectConversationID.derive(a, b) == "dm:6cYTxM8ClUCmVDDNvdTauZgIRzZyE4LJU8QEDpho4OE")
        #expect(DirectConversationID.derive(b, a) == DirectConversationID.derive(a, b))
        #expect(DirectConversationID.derive(a, a) == nil)
        #expect(DirectConversationID.derive(a, "agent-1") == nil)
    }
    @Test func agentChatUsesTheOwnRootFromAccountStatus() async {
        let own = String(repeating: "ERER", count: 10) + "ERE", agent = String(repeating: "IiIi", count: 10) + "IiI"
        let transport = ProxyTransport { request in request.method == "account.status" ? .object(["principal_commitment": .string(own)]) : .object([:]) }
        let client = RamfluxClient(transport: transport), repository = NativeAgentsRepository(client: client, updates: NativeUpdateSource(client: client))
        guard case .success(let id) = await repository.chatConversation(account: "a", agent: agent) else { Issue.record("no conversation"); return }
        #expect(id == "dm:6cYTxM8ClUCmVDDNvdTauZgIRzZyE4LJU8QEDpho4OE")
        guard case .failure(.unavailableResource("agents.unavailable.chat")) = await repository.chatConversation(account: "a", agent: "not-an-anchor") else { Issue.record("bad anchor accepted"); return }
    }
}
