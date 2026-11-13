// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
struct ContactsRepositoryTests {
    @Test func exactRequestDecisionAndAllSafetyGroupsArePreserved() async {
        let transport = ProxyTransport { request in
            switch request.method {
            case "contact.verification.status": return .object(["contact_identity_commitment": .string("root"), "safety_number": .array([.string("12345"),.string("67890")]), "fingerprint_hex": .string("fingerprint"), "verification_state": .string("key_changed"), "stored_verification_state": .string("verified")])
            case "contact.request.block":
                #expect(request.body["request_id"] == .string("request")); #expect(request.operationID?.rawValue == "stable")
                return .object([:])
            default: return .object([:])
            }
        }
        let client = RamfluxClient(transport: transport), updates = NativeUpdateSource(client: RamfluxClient(transport: transport))
        let repo = NativeContactsRepository(client: client, updates: updates)
        let contact = ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer", rootCommitment: "root")
        guard case .success(let safety) = await repo.safety(account: "a", contact: contact) else { Issue.record("Safety mapping failed"); return }
        #expect(safety.number == "12345 67890"); #expect(!safety.verified); #expect(safety.requiresReview)
        _ = await repo.decide(account: "a", request: "request", decision: .block, operationID: "stable")
        #expect(transport.calls.withLock { $0.last?.method } == "contact.request.block")
    }
}
