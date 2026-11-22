// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import Synchronization
public enum RepositoryUpdate: Equatable, Sendable { case invalidated, failed(AppFailure) }
/// One logical observer of account invalidations. Any number may be live at once; `stop()` is idempotent
/// and returns after the shared native subscription has stopped if this was its last observer.
public final class RepositoryObservation: Sendable {
    public let stream: AsyncStream<RepositoryUpdate>
    private let onStop: @Sendable () async -> Void
    private let stopCalled = Mutex(false)
    public init(failure: AppFailure) { onStop = {}; stream = AsyncStream { $0.yield(.failed(failure)); $0.finish() } }
    public init(stream: AsyncStream<RepositoryUpdate>, onStop: @escaping @Sendable () async -> Void = {}) { self.onStop = onStop; self.stream = stream }
    public func stop() async { let call = stopCalled.withLock { value in let old = value; value = true; return !old }; if call { await onStop() } }
}
/// Shared event fan-out: one native subscription per active account, multicast to every observer.
/// The subscription opens with the first observer and stops with the last. A queue overflow, lag
/// notification or byte-credit exhaustion (`resyncRequired`) resubscribes automatically and tells every
/// observer to reload (`.invalidated`); any other failure is broadcast as `.failed` and ends all observers.
/// Observing a different account ends the previous account's observers before the new subscription opens.
public actor NativeUpdateSource {
    static let topics = ["conversation.changed", "call.changed", "task.changed", "mcp.approval.request", "mcp.approval.granted", "mcp.approval.denied", "message.changed", "message.updated", "group.changed", "group.state.conflict", "group.state.delivery_failed", "contact.changed", "contact.requested", "contact.accepted", "contact.declined", "contact.blocked", "account.state"]
    /// Consecutive resubscriptions without a delivered event before the hub reports a failure.
    static let resyncLimit = 4
    private let client: RamfluxClient
    private var account: String?
    private var observers: [UUID: AsyncStream<RepositoryUpdate>.Continuation] = [:]
    private var subscription: EventSubscription?
    private var pump: Task<Void, Never>?
    private var epoch: UInt64 = 0
    private var resyncs = 0
    private var tail: Task<Void, Never>?
    public init(client: RamfluxClient) { self.client = client }
    /// Number of live observers; for tests and diagnostics.
    public var observerCount: Int { observers.count }
    public func observe(account: String) async -> RepositoryObservation {
        let id = UUID()
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        await serialized { hub in await hub.join(id: id, account: account, continuation: pair.continuation) }
        return RepositoryObservation(stream: pair.stream, onStop: { [weak self] in await self?.remove(id) })
    }
    private func remove(_ id: UUID) async {
        await serialized { hub in await hub.leave(id: id) }
    }
    /// Membership and native lifecycle changes run one at a time; the pump never awaits this chain.
    private func serialized(_ work: @escaping @Sendable (NativeUpdateSource) async -> Void) async {
        let previous = tail
        let next = Task { await previous?.value; await work(self) }
        tail = next; await next.value
    }
    private func join(id: UUID, account: String, continuation: AsyncStream<RepositoryUpdate>.Continuation) async {
        if self.account != account { await close(finishing: true); self.account = account }
        observers[id] = continuation
        if subscription == nil { await open() } else { continuation.yield(.invalidated) }
    }
    private func leave(id: UUID) async {
        guard let continuation = observers.removeValue(forKey: id) else { return }
        continuation.finish()
        if observers.isEmpty { await close(finishing: false); account = nil }
    }
    private func open() async {
        guard let account, !observers.isEmpty else { return }
        do {
            try await client.resetEvents()
            let filter = try SubscriptionFilter(accountID: account, topics: Self.topics, attendedFrontend: true)
            let opened = try await client.events(filter)
            epoch &+= 1; let current = epoch
            subscription = opened
            pump = Task { [weak self] in
                do {
                    for try await _ in opened.stream { await self?.delivered(epoch: current) }
                    await self?.ended(epoch: current, failure: nil)
                } catch { await self?.ended(epoch: current, failure: error) }
            }
            broadcast(.invalidated)
        } catch { fail(AppFailure.map(error)) }
    }
    private func close(finishing: Bool) async {
        epoch &+= 1
        let stopping = subscription, joining = pump
        subscription = nil; pump = nil
        stopping?.cancel(); await stopping?.stop(); await joining?.value
        if finishing { for continuation in observers.values { continuation.finish() }; observers.removeAll(); resyncs = 0 }
    }
    private func delivered(epoch current: UInt64) {
        guard current == epoch else { return }
        resyncs = 0; broadcast(.invalidated)
    }
    private func ended(epoch current: UInt64, failure: (any Error)?) {
        guard current == epoch else { return }
        Task { await serialized { hub in await hub.recover(epoch: current, failure: failure) } }
    }
    private func recover(epoch current: UInt64, failure: (any Error)?) async {
        guard current == epoch else { return }
        let resync = (failure as? BridgeError) == .resyncRequired || (failure as? CoreFailure)?.code == .resyncRequired
        guard resync, resyncs < Self.resyncLimit else {
            await close(finishing: false)
            if let failure { fail(AppFailure.map(failure)) } else { finishAll() }
            return
        }
        resyncs += 1
        await close(finishing: false)
        try? await Task.sleep(for: .milliseconds(25 * resyncs))
        await open()
    }
    private func broadcast(_ update: RepositoryUpdate) { for continuation in observers.values { continuation.yield(update) } }
    private func fail(_ failure: AppFailure) { broadcast(.failed(failure)); finishAll() }
    private func finishAll() {
        for continuation in observers.values { continuation.finish() }
        observers.removeAll(); account = nil; resyncs = 0
    }
    deinit { subscription?.cancel(); pump?.cancel() }
}
