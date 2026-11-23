// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Synchronization
import RamfluxCore
@testable import AppData
private func failure(_ result: RepositoryResult<Void>) -> AppFailure? { if case .failure(let value) = result { value } else { nil } }
private func ok(_ result: RepositoryResult<Void>) -> Bool { if case .success = result { true } else { false } }
struct ContactChangeTests {
    private func repository(_ transport: ProxyTransport) -> NativeContactsRepository {
        NativeContactsRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
    }
    private let expected: JSONValue = .object(["contact_identity_commitment": .string("root"), "self_identity_commitment": .string("me"), "safety_number_hash": .string("h"), "contact_device_set_hash": .string("d")])
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
    @Test func verifySendsTheComparedSnapshotAsTheCompareAndSetExpectation() async {
        let expected = expected
        let transport = ProxyTransport { request in
            switch request.method {
            case "contact.verification.status": return .object(["contact_identity_commitment": .string("root"), "verification_state": .string("unverified"), "expected": expected])
            default: return .object(["verification_state": .string("verified")])
            }
        }
        let repo = repository(transport)
        let contact = ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer", rootCommitment: "root")
        #expect(ok(await repo.change(account: "a", contact: contact, change: .verify, operationID: "op")))
        let calls = transport.calls.withLock { $0 }
        #expect(calls.map(\.method) == ["contact.verification.status", "contact.verify"])
        #expect(calls[1].body == .object(["expected": expected]))
    }
    @Test func verifyRefusesASnapshotForAnotherIdentity() async {
        let transport = ProxyTransport { _ in .object(["contact_identity_commitment": .string("other"), "expected": .object([:])]) }
        let contact = ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer", rootCommitment: "root")
        #expect(failure(await repository(transport).change(account: "a", contact: contact, change: .verify, operationID: "op")) == .invalidData)
        // Nothing was verified; the second status read is the reconciliation, which finds no verified state.
        #expect(!transport.calls.withLock { $0.map(\.method) }.contains("contact.verify"))
    }
    @Test func aVerifyWithALostReplyIsReconciledByReadingTheStateAgain() async {
        let expected = expected
        let recorded = Mutex(false)
        let transport = ProxyTransport { request in
            switch request.method {
            case "contact.verification.status":
                return .object(["contact_identity_commitment": .string("root"), "verification_state": .string(recorded.withLock { $0 } ? "verified" : "unverified"),
                                "safety_number": .string("12345 67890"), "fingerprint_hex": .string("f"), "expected": expected])
            default:
                // The SDK records the verification, but the reply is lost on the way back.
                recorded.withLock { $0 = true }; throw CoreFailure(code: 6, effect: .unknown)
            }
        }
        let contact = ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer", rootCommitment: "root")
        #expect(ok(await repository(transport).change(account: "a", contact: contact, change: .verify, operationID: "op")))
        #expect(transport.calls.withLock { $0.map(\.method) } == ["contact.verification.status", "contact.verify", "contact.verification.status"])
    }
    @Test func aRefusedVerifyStaysRefusedWhenTheStateIsNotVerified() async {
        let expected = expected
        let transport = ProxyTransport { request in
            switch request.method {
            case "contact.verification.status":
                return .object(["contact_identity_commitment": .string("root"), "verification_state": .string("unverified"),
                                "safety_number": .string("12345 67890"), "fingerprint_hex": .string("f"), "expected": expected])
            default: throw CoreFailure(code: 6, effect: .unknown)
            }
        }
        let contact = ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer", rootCommitment: "root")
        #expect(failure(await repository(transport).change(account: "a", contact: contact, change: .verify, operationID: "op")) != nil)
    }
    @Test func contactRowsCarryTheirLinkAndBlockState() async {
        let transport = ProxyTransport { _ in .object(["contacts": .array([.object(["principal_id": .string("peer"), "link_id": .string("link"), "blocked": .bool(true)])])]) }
        guard case .success(let page) = await repository(transport).contactsPage(account: "a", query: "", cursor: nil, limit: 10) else { Issue.record("page failed"); return }
        #expect(page.rows.first?.linkID == "link"); #expect(page.rows.first?.blocked == true); #expect(page.nextCursor == nil)
    }
}
