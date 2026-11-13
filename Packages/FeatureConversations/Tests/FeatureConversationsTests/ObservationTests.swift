// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Observation
import Testing
import AppData
@testable import FeatureConversations
private actor ControlledDirectory: ConversationsRepository {
    nonisolated let reads = AsyncStream<Int>.makeStream()
    nonisolated let stopped = AsyncStream<Void>.makeStream()
    nonisolated let updates = Mutex<AsyncStream<RepositoryUpdate>.Continuation?>(nil)
    private var count = 0
    private var waiting: [Int: CheckedContinuation<RepositoryResult<[ConversationRecord]>, Never>] = [:]
    func list(account: String) async -> RepositoryResult<[ConversationRecord]> {
        count += 1; let id = count
        return await withCheckedContinuation { waiting[id] = $0; reads.continuation.yield(id) }
    }
    func shutdown() {
        for continuation in waiting.values { continuation.resume(returning: .failure(.failed)) }; waiting = [:]
        reads.continuation.finish(); updates.withLock { $0?.finish() }; stopped.continuation.finish()
    }
    func release(_ id: Int, _ rows: [ConversationRecord]) { waiting.removeValue(forKey: id)?.resume(returning: .success(rows)) }
    func search(account: String, query: String) -> RepositoryResult<[ConversationRecord]> { .failure(.unsupported) }
    func observe(account: String) -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates.withLock { $0 = pair.continuation }; pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish(); self.stopped.continuation.yield(()) })
    }
    nonisolated func emit(_ update: RepositoryUpdate, terminal: Bool = false) { updates.withLock { $0?.yield(update); if terminal { $0?.finish() } } }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct ObservationTests {
    private func invalidationBarrier(_ vm: ConversationsViewModel, _ repo: ControlledDirectory) async {
        let pair = AsyncStream<Bool>.makeStream()
        let deadline = Task { try? await Task.sleep(for: .seconds(5)); pair.continuation.finish() }
        defer { deadline.cancel(); pair.continuation.finish() }
        withObservationTracking { _ = vm.state.failure } onChange: { pair.continuation.yield(true) }
        repo.emit(.invalidated)
        var events = pair.stream.makeAsyncIterator(); #expect(await events.next() == true)
    }
    @Test func invalidationCoalescesBlockedReadGapReopensAndLateReadCannotRepopulate() async {
        let repo = ControlledDirectory(), vm = ConversationsViewModel(repository: repo, account: "a", emit: { _ in })
        let deadline = Task { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled { await repo.shutdown() } }
        defer { deadline.cancel() }
        var reads = repo.reads.stream.makeAsyncIterator(), stops = repo.stopped.stream.makeAsyncIterator()
        vm.send(.appeared); #expect(await reads.next() == 1)
        // A failure is an ordered barrier after the initial invalidation. Its visible state
        // proves the ViewModel consumed that invalidation while read 1 was still blocked.
        await invalidationBarrier(vm, repo)
        await repo.release(1, [ConversationRecord(id: "old", title: "Old", preview: "")])
        #expect(await reads.next() == 2)
        repo.emit(.failed(.resyncRequired), terminal: true); _ = await stops.next(); await vm.joinObservation(); #expect(vm.state.failure == .resyncRequired)
        await repo.release(2, []); await vm.settle()
        vm.send(.refresh); #expect(await reads.next() == 3)
        // Confirm a terminal observer is replaceable; the new initial invalidation is
        // ordered before this visible barrier, so another read is coalesced.
        await invalidationBarrier(vm, repo)
        vm.send(.disappeared); _ = await stops.next()
        await repo.release(3, [ConversationRecord(id: "late", title: "Late", preview: "")]); await vm.settle()
        #expect(vm.state.rows.isEmpty)
    }
}
