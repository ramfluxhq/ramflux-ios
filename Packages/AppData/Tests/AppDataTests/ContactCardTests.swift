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

@Suite(.timeLimit(.minutes(1))) struct ContactAddByCardTests {
    @Test func aCardIsAddedAsACardAndAnIdAsAPrincipal() async {
        let transport = ProxyTransport { request in
            #expect(request.method == "contact.add")
            let card = request.body["card"]?.string, principal = request.body["principal_id"]?.string
            #expect((card?.hasPrefix("ramflux-card:") ?? false) != (principal != nil))
            return .object(["ok": .bool(true)])
        }
        let client = RamfluxClient(transport: transport)
        let repository = NativeContactsRepository(client: client, updates: NativeUpdateSource(client: client))
        _ = await repository.add(account: "a", principal: "ramflux-card:v3:" + String(repeating: "x", count: 4000), operationID: "op1")
        _ = await repository.add(account: "a", principal: "principal-abc", operationID: "op2")
        #expect(transport.calls.withLock { $0.count } == 2)
    }
}

@Suite struct AlreadyContactRefusalTests {
    /// A card for an existing contact is refused with already_contact; that is definite, so the add does
    /// not stay unresolved behind "Reconcile original contact action".
    @Test func alreadyContactIsADefiniteRefusal() {
        let failure = AppFailure.map(CoreFailure(code: 9, effect: .unknown, operationID: "op", reasonCode: "already_contact"))
        #expect(failure == .typedRefusal("already_contact"))
        #expect(RetainedMutation<String, Void>.Snapshot(arguments: "x", operationID: "op", result: .failure(failure)).unresolved == false)
    }
}
