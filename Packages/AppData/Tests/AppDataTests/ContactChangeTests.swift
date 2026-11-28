// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
private func failure(_ result: RepositoryResult<Void>) -> AppFailure? { if case .failure(let value) = result { value } else { nil } }
private func ok(_ result: RepositoryResult<Void>) -> Bool { if case .success = result { true } else { false } }
struct ContactChangeTests {
    private func repository(_ transport: ProxyTransport) -> NativeContactsRepository {
        NativeContactsRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
    }
    @Test func linkChangesSelectTheFriendLinkAndRemoveOnlyFromThisAccount() async {
        let transport = ProxyTransport { _ in .object([:]) }
        let repo = repository(transport)
        let contact = ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer", linkID: "link-1")
        for change in [ContactChange.remove, .block, .unblock] { #expect(ok(await repo.change(account: "a", contact: contact, change: change, operationID: "op-\(change.rawValue)"))) }
        let calls = transport.calls.withLock { $0 }
        #expect(calls.map(\.method) == ["contact.remove", "contact.block", "contact.unblock"])
        #expect(calls[0].body == .object(["link_id": .string("link-1"), "scope": .string("me")]))
        #expect(calls[1].body == .object(["link_id": .string("link-1")])); #expect(calls[2].operationID?.rawValue == "op-unblock")
        let unlinked = ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer")
        #expect(failure(await repo.change(account: "a", contact: unlinked, change: .block, operationID: "x")) == .invalidInput)
    }
    @Test func contactRowsCarryTheirLinkAndBlockState() async {
        let transport = ProxyTransport { _ in .object(["contacts": .array([.object(["principal_id": .string("peer"), "link_id": .string("link"), "blocked": .bool(true)])])]) }
        guard case .success(let page) = await repository(transport).contactsPage(account: "a", query: "", cursor: nil, limit: 10) else { Issue.record("page failed"); return }
        #expect(page.rows.first?.linkID == "link"); #expect(page.rows.first?.blocked == true); #expect(page.nextCursor == nil)
    }
}
