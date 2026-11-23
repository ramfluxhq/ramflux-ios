// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import AppData
@testable import FeatureContacts
/// 50,000 contacts and 50,000 inbound requests behind the snapshot pager, like the native repository.
private final class SyntheticContacts: ContactsRepository, Sendable {
    let reads = Mutex(0)
    let changes = Mutex<[String]>([])
    private let contactPager = SnapshotPager<ContactRecord>(), requestPager = SnapshotPager<ContactRequestRecord>()
    func contacts(account: String) async -> RepositoryResult<[ContactRecord]> {
        reads.withLock { $0 += 1 }
        return .success((0..<50_000).map { ContactRecord(id: String(format: "p%05d", $0), displayName: $0 % 10 == 0 ? "Ten \($0)" : "Name \($0)", subtitle: "", rootCommitment: "root\($0)", linkID: "link\($0)", blocked: $0 == 1) })
    }
    func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]> {
        .success((0..<50_000).map { ContactRequestRecord(id: "r\($0)", principal: "s\($0)", name: "Stranger \($0)", direction: $0 % 2 == 0 ? "inbound" : "outbound", state: "pending") })
    }
    func contactsPage(account: String, query: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRecord>> {
        await contactPager.page(cursor: cursor, limit: limit, read: { await self.contacts(account: account) }, include: { ContactRecord.matches($0, query) })
    }
    func requestsPage(account: String, direction: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<ContactRequestRecord>> {
        await requestPager.page(cursor: cursor, limit: limit, read: { await self.requests(account: account) }, include: { $0.direction == direction })
    }
    func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void> { .success(()) }
    func change(account: String, contact: ContactRecord, change: ContactChange, operationID: String) async -> RepositoryResult<Void> { changes.withLock { $0.append(contact.id + ":" + change.rawValue) }; return .success(()) }
    func safety(account: String, contact: ContactRecord) async -> RepositoryResult<ContactSafety> { .success(ContactSafety(root: contact.rootCommitment ?? "", number: "12345", fingerprint: "f", verified: false, requiresReview: false)) }
    func observe(account: String) async -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
    func unavailable(_ capability: ContactUnavailable) -> AppFailure { .unsupported }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct ContactsWindowTests {
    @Test func fiftyThousandContactsAndRequestsStayInsideTheWindow() async {
        let source = SyntheticContacts(), model = ContactsViewModel(repository: source, account: "a", emit: { _ in })
        let clock = ContinuousClock()
        let first = await clock.measure { model.send(.refresh); await model.settle() }
        #expect(model.state.contacts.count == 50); #expect(model.state.canLoadMore)
        var scroll = Duration.zero, pages = 0
        while model.state.canLoadMore && pages < 999 { scroll += await clock.measure { model.send(.loadMore); await model.settle() }; pages += 1; #expect(model.state.contacts.count <= 300) }
        #expect(model.state.contacts.last?.id == "p49999"); #expect(model.state.canLoadBefore); #expect(source.reads.withLock { $0 } <= 2) // the first read and the reload when the observation goes live; scrolling re-reads nothing
        let filter = await clock.measure { model.send(.filter("Ten")); await model.settle() }
        #expect(model.state.contacts.count == 50); #expect(model.state.contacts.allSatisfy { $0.displayName.hasPrefix("Ten") }); #expect(!model.state.canLoadBefore)
        model.send(.mode(.strangers)); await model.settle()
        #expect(model.state.requests.count == 50); #expect(model.state.requests.allSatisfy { $0.direction == "inbound" })
        var requestScroll = Duration.zero
        for _ in 0..<100 { requestScroll += await clock.measure { model.send(.loadMore); await model.settle() } }
        #expect(model.state.requests.count == 300)
        print("CONTACTS_50K first=\(first) scroll999=\(scroll) filter=\(filter) requests100=\(requestScroll) listReads=\(source.reads.withLock { $0 })")
        model.send(.disappeared)
    }
    @Test func profileChangesNeedConfirmationAndMatchTheContactState() async {
        let source = SyntheticContacts()
        let model = ContactsViewModel(repository: source, account: "a", state: ContactsState(mode: .profile("p00001")), emit: { _ in })
        model.send(.refresh); await model.settle()
        #expect(model.state.selected?.blocked == true)
        model.send(.requestChange(.block)); #expect(model.state.pendingChange == nil)
        model.send(.requestChange(.verify)); #expect(model.state.pendingChange == nil)
        model.send(.requestChange(.unblock)); #expect(model.state.pendingChange?.change == .unblock); #expect(source.changes.withLock { $0 }.isEmpty)
        model.send(.confirmChange); await model.settle(); #expect(source.changes.withLock { $0 } == ["p00001:unblock"]); #expect(model.state.pendingChange == nil)
        model.send(.disappeared)
    }
    @Test func verifyIsOfferedOnlyForTheFreshUnverifiedSafetyNumberAndRemoveLeaves() async {
        let source = SyntheticContacts(); var events: [ContactsEvent] = []
        let model = ContactsViewModel(repository: source, account: "a", state: ContactsState(mode: .safety("p00002")), emit: { events.append($0) })
        model.send(.refresh); await model.settle()
        #expect(model.state.safety?.number == "12345"); #expect(model.state.safetyPrincipal == "p00002")
        model.send(.requestChange(.verify)); #expect(model.state.pendingChange?.change == .verify)
        model.send(.confirmChange); await model.settle(); #expect(source.changes.withLock { $0 } == ["p00002:verify"])
        model.send(.requestChange(.remove)); model.send(.confirmChange); await model.settle()
        #expect(events == [.navigate(.contacts)])
        model.send(.disappeared)
    }
}
