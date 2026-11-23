// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData

/// Expected values were produced by the reference `blake3` 1.8.7 crate and the SDK's `dm_scope::derive` rule.
struct DirectConversationIDTests {
    private func hex(_ bytes: [UInt8]?) -> String? { bytes.map { $0.map { String(format: "%02x", $0) }.joined() } }
    @Test func singleChunkBlake3MatchesTheReferenceImplementation() {
        #expect(hex(BLAKE3.hashSingleChunk([])) == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
        #expect(hex(BLAKE3.hashSingleChunk(Array("abc".utf8))) == "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85")
        #expect(hex(BLAKE3.hashSingleChunk([UInt8](repeating: 1, count: 64))) == "29c04cc4ce7b05d941850b358b7dfd7e6285cc54e63e2e239804c1781c3d2497")
        #expect(hex(BLAKE3.hashSingleChunk([UInt8](repeating: 7, count: 131))) == "b50716c931c8f7291ac3d5f6839b90ea1a60be115adbb61e473e2a1b542b8fd5")
        #expect(hex(BLAKE3.hashSingleChunk([UInt8](repeating: 2, count: 1024))) == "fa8af17567c147993830cdd42cea9d8a8f157c9b98b4e7ef5677f417a5d8ae61")
        #expect(BLAKE3.hashSingleChunk([UInt8](repeating: 0, count: 1025)) == nil)
    }
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
