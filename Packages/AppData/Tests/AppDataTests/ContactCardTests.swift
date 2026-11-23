// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData

@Suite(.timeLimit(.minutes(1))) struct ContactCardTests {
    @Test func ownCardReadsContactCardExportAndRefusesAMalformedReply() async {
        let transport = ProxyTransport { request in
            #expect(request.method == "contact.card.export"); #expect(request.accountID == "account")
            return .object(["card": .string("ramflux-card:v3:abc"), "link": .string("ramflux://contact/v3/abc")])
        }
        let client = RamfluxClient(transport: transport)
        let repository = NativeContactsRepository(client: client, updates: NativeUpdateSource(client: client))
        #expect(await repository.ownCard(account: "account") == .success(ContactCardExport(card: "ramflux-card:v3:abc", link: "ramflux://contact/v3/abc")))
        let broken = ProxyTransport { _ in .object(["card": .string("only")]) }
        let other = NativeContactsRepository(client: RamfluxClient(transport: broken), updates: NativeUpdateSource(client: RamfluxClient(transport: broken)))
        guard case .failure = await other.ownCard(account: "account") else { Issue.record("A reply without a link must fail"); return }
    }
}
