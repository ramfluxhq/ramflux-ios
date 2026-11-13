// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Observation
import Testing
import AppData
@testable import FeatureContacts
private actor SafetyDirectory: ContactsRepository {
    enum Authority { case present, removed, locked, offline }
    var authority: Authority = .present
    nonisolated let updates = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
    func set(_ value: Authority) { authority = value }
    func contacts(account: String) -> RepositoryResult<[ContactRecord]> {
        switch authority {
        case .present: .success([ContactRecord(id: "peer", displayName: "Peer", subtitle: "peer", verified: true, rootCommitment: "root")])
        case .removed: .success([])
        case .locked: .failure(.locked)
        case .offline: .failure(.offline)
        }
    }
    func requests(account: String) -> RepositoryResult<[ContactRequestRecord]> { .success([]) }
    func add(account: String, principal: String, operationID: String) -> RepositoryResult<Void> { .failure(.unsupported) }
    func decide(account: String, request: String, decision: ContactDecision, operationID: String) -> RepositoryResult<Void> { .failure(.unsupported) }
    func safety(account: String, contact: ContactRecord) -> RepositoryResult<ContactSafety> { .success(ContactSafety(root: "root", number: "12345", fingerprint: "fingerprint", verified: true, requiresReview: false)) }
    func observe(account: String) -> RepositoryObservation { updates.continuation.yield(.invalidated); return RepositoryObservation(stream: updates.stream, onStop: { self.updates.continuation.finish() }) }
    nonisolated func unavailable(_ capability: ContactUnavailable) -> AppFailure { .unsupported }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct SafetyFreshnessTests {
    @Test func terminalFailuresAndUnexpectedFinishImmediatelyRevokeVerifiedDisplay() async {
        for failure in [AppFailure.locked, .offline, .resyncRequired] {
            let repo = SafetyDirectory(), model = ContactsViewModel(repository: SafetyDirectory(), account: "unused", emit: { _ in }); model.send(.disappeared)
            let vm = ContactsViewModel(repository: repo, account: "a", state: ContactsState(mode: .safety("peer")), emit: { _ in })
            vm.send(.refresh); await vm.settle(); #expect(vm.state.safety?.verified == true)
            let signal = AsyncStream<Void>.makeStream(); let deadline = Task { try? await Task.sleep(for: .seconds(5)); signal.continuation.finish() }
            withObservationTracking { _ = vm.state.safety } onChange: { signal.continuation.yield(()) }
            repo.updates.continuation.yield(.failed(failure)); repo.updates.continuation.finish()
            var iterator = signal.stream.makeAsyncIterator(); #expect(await iterator.next() != nil); deadline.cancel(); signal.continuation.finish()
            #expect(vm.state.safety == nil); #expect(vm.state.safetyPrincipal == nil); #expect(vm.state.safetyStale)
            vm.send(.disappeared)
        }
        let repo = SafetyDirectory(), vm = ContactsViewModel(repository: SafetyDirectory(), account: "unused", emit: { _ in }); vm.send(.disappeared)
        let model = ContactsViewModel(repository: repo, account: "a", state: ContactsState(mode: .safety("peer")), emit: { _ in })
        model.send(.refresh); await model.settle(); #expect(model.state.safety?.verified == true)
        let signal = AsyncStream<Void>.makeStream(); let deadline = Task { try? await Task.sleep(for: .seconds(5)); signal.continuation.finish() }
        withObservationTracking { _ = model.state.safety } onChange: { signal.continuation.yield(()) }
        repo.updates.continuation.finish(); var iterator = signal.stream.makeAsyncIterator(); #expect(await iterator.next() != nil); deadline.cancel(); signal.continuation.finish()
        #expect(model.state.safety == nil); model.send(.disappeared)
    }
    @Test func removedLockedAndOfflineAuthorityCannotKeepVerifiedSafety() async {
        let repo = SafetyDirectory()
        let model = ContactsViewModel(repository: repo, account: "a", state: ContactsState(mode: .safety("peer")), emit: { _ in })
        model.send(.refresh); await model.settle()
        #expect(model.state.safety?.verified == true); #expect(model.state.safetyPrincipal == "peer")
        for authority in [SafetyDirectory.Authority.removed, .locked, .offline] {
            await repo.set(authority)
            let observed = AsyncStream<Void>.makeStream()
            let deadline = Task { try? await Task.sleep(for: .seconds(5)); observed.continuation.finish() }
            withObservationTracking { _ = model.state.safety } onChange: { observed.continuation.yield(()) }
            repo.updates.continuation.yield(.invalidated)
            var stream = observed.stream.makeAsyncIterator(); #expect(await stream.next() != nil); deadline.cancel(); observed.continuation.finish()
            await model.settle(); #expect(model.state.safety == nil); #expect(model.state.safetyPrincipal == nil)
            await repo.set(.present); model.send(.refresh); await model.settle(); #expect(model.state.safety?.verified == true)
        }
        model.send(.mode(.contacts)); model.send(.filter("missing")); #expect(model.state.visibleContacts.isEmpty)
        model.send(.filter("Peer")); #expect(model.state.visibleContacts.map(\.id) == ["peer"])
        model.send(.disappeared)
    }
}
