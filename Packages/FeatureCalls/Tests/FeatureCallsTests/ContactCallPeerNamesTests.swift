// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import Synchronization
import AppData
@testable import FeatureCalls

private final class RosterFake: ContactsRepository, Sendable {
    let reads = Mutex(0)
    let roster: [ContactRecord]
    init(count: Int) { roster = (0..<count).map { ContactRecord(id: "p\($0)", displayName: $0 == 3 ? "p3" : "Name \($0)", subtitle: "p\($0)") } }
    func contacts(account: String) async -> RepositoryResult<[ContactRecord]> { .success(roster) }
    func contactsPage(account: String, query: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRecord>> {
        reads.withLock { $0 += 1 }
        let start = Int(cursor ?? "0") ?? 0, end = min(roster.count, start + limit)
        return .success(RowPage(rows: Array(roster[start..<end]), nextCursor: end < roster.count ? String(end) : nil))
    }
    func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]> { .success([]) }
    func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .unsupported) }
    func unavailable(_ capability: ContactUnavailable) -> AppFailure { .unsupported }
}

@Suite(.timeLimit(.minutes(1))) struct ContactCallPeerNamesTests {
    @Test func namesPeersInBatchesAndStopsOnceAllAreFound() async {
        let roster = RosterFake(count: 50_000)
        let names = await ContactCallPeerNames(contacts: roster, batch: 200).names(account: "a", peers: ["p1", "p3", "p450"])
        #expect(names == ["p1": "Name 1", "p450": "Name 450"])
        #expect(roster.reads.withLock { $0 } == 3)
    }
    @Test func unknownPeersReadTheWholeRosterOnceAndStayUnnamed() async {
        let roster = RosterFake(count: 1_000)
        #expect(await ContactCallPeerNames(contacts: roster, batch: 200).names(account: "a", peers: ["stranger"]).isEmpty)
        #expect(roster.reads.withLock { $0 } == 5)
        #expect(await ContactCallPeerNames(contacts: roster).names(account: "a", peers: []).isEmpty)
    }
}
