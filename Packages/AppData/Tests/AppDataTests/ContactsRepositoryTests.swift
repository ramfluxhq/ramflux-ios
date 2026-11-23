// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Synchronization
import Testing
import RamfluxCore
@testable import AppData
struct ContactsRepositoryTests {
    @Test func exactRequestDecisionAndAllSafetyGroupsArePreserved() async {
        let transport = ProxyTransport { request in
            switch request.method {
            case "contact.verification.status": return .object(["contact_identity_commitment": .string("root"), "safety_number": .array([.string("12345"),.string("67890")]), "fingerprint_hex": .string("fingerprint"), "verification_state": .string("key_changed"), "stored_verification_state": .string("verified")])
            case "contact.block":
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
        #expect(transport.calls.withLock { $0.last?.method } == "contact.block")
    }
}
@Suite(.timeLimit(.minutes(1))) struct ContactSnapshotScaleTests {
    /// 50,000 rows exceed the 1 MiB response ceiling of both the SDK local bus and this bridge, so the decode
    /// path is exercised directly; the ceiling itself is checked below.
    @Test func fiftyThousandRowsDecodeInChunksAndPageThroughTheWindow() async throws {
        let rows: [JSONValue] = (0..<50_000).map { .object(["principal_id": .string("p\($0)"), "display_name": .string("Contact \($0)")]) }
        let clock = ContinuousClock(), start = clock.now
        let records = try await ProxyGateway.mapRows(.object(["contacts": .array(rows)]), "contacts") { row in
            ContactRecord(id: try ProxyGateway.text(row, "principal_id"), displayName: row["display_name"]?.string ?? "", subtitle: "", verified: nil)
        }
        let decoded = clock.now - start
        #expect(records.count == 50_000); #expect(records.last?.id == "p49999")
        let pager = SnapshotPager<ContactRecord>()
        let read: RowPageReader<ContactRecord> = { cursor, limit in await pager.page(cursor: cursor, limit: limit, read: { .success(records) }) }
        guard case .success(var window) = await RowWindow<ContactRecord>.first(read) else { Issue.record("first page failed"); return }
        for _ in 0..<20 { if case .success(let next) = await window.after(read) { window = next } }
        #expect(window.count <= RowWindow<ContactRecord>.defaultMaxRows); #expect(window.canLoadAfter)
        print("CONTACTS_50K decode=\(decoded) total=\(clock.now - start) window=\(window.count)")
    }
    @Test func moreThan4096ContactsDecodeAndTheByteCeilingStillRefusesOversizedResponses() async {
        let rows: @Sendable (Int) -> [JSONValue] = { count in (0..<count).map { .object(["principal_id": .string("p\($0)")]) } }
        let size = Mutex(5_000)
        let transport = ProxyTransport { request in request.method == "contact.list" ? .object(["contacts": .array(rows(size.withLock { $0 }))]) : .object([:]) }
        let client = RamfluxClient(transport: transport)
        let repository = NativeContactsRepository(client: client, updates: NativeUpdateSource(client: client))
        guard case .success(let all) = await repository.contacts(account: "a") else { Issue.record("5,000 contacts did not decode"); return }
        #expect(all.count == 5_000)
        size.withLock { $0 = 50_000 }
        guard case .failure = await repository.contacts(account: "a") else { Issue.record("a response above 1 MiB was accepted"); return }
    }
}
