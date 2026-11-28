// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import Synchronization
public enum RepositoryUpdate: Equatable, Sendable { case invalidated, failed(AppFailure) }
/// A live `message.transient` frame (for example a typing indicator), delivered only to observers that
/// asked for transient frames. `body` is the frame body as JSON bytes; transient frames are never replayed.
public struct TransientFrame: Equatable, Sendable {
    public let topic: String
    public let body: Data
    public init(topic: String, body: Data) { self.topic = topic; self.body = body }
}
/// The body of a payload-carrying account event (`contact.identity_changed`, `conversation.devices_changed`),
/// delivered only to observers that asked for event frames. `body` is the frame body as JSON bytes. The body is
/// handed to the parser and never logged.
public struct EventFrame: Equatable, Sendable {
    public let topic: String
    public let body: Data
    public init(topic: String, body: Data) { self.topic = topic; self.body = body }
}
/// One logical observer of account invalidations. Any number may be live at once; `stop()` is idempotent
/// and returns after the shared native subscription has stopped if this was its last observer.
public final class RepositoryObservation: Sendable {
    public let stream: AsyncStream<RepositoryUpdate>
    /// Transient frames; `nil` unless the observer asked for them. It finishes with `stream`.
    public let transient: AsyncStream<TransientFrame>?
    /// Payload frames of the identity topics; `nil` unless the observer asked for them. It finishes with `stream`.
    public let events: AsyncStream<EventFrame>?
    private let onStop: @Sendable () async -> Void
    private let stopCalled = Mutex(false)
    public init(failure: AppFailure) { onStop = {}; transient = nil; events = nil; stream = AsyncStream { $0.yield(.failed(failure)); $0.finish() } }
    public init(stream: AsyncStream<RepositoryUpdate>, transient: AsyncStream<TransientFrame>? = nil, events: AsyncStream<EventFrame>? = nil, onStop: @escaping @Sendable () async -> Void = {}) { self.onStop = onStop; self.stream = stream; self.transient = transient; self.events = events }
    public func stop() async { let call = stopCalled.withLock { value in let old = value; value = true; return !old }; if call { await onStop() } }
}
/// Shared event fan-out: one native subscription per active scope (an account, or the daemon-scoped
/// backup job stream used before any account exists), multicast to every observer.
/// The subscription opens with the first observer and stops with the last. A queue overflow, lag
/// notification or byte-credit exhaustion (`resyncRequired`) resubscribes automatically and tells every
/// observer to reload (`.invalidated`); any other failure is broadcast as `.failed` and ends all observers.
/// Observing a different scope ends the previous scope's observers before the new subscription opens.
/// Whether one `unattended` call holds a count of `detached`.
final class LeaseMark: Sendable { let flag = Mutex(false) }
public actor NativeUpdateSource {
    /// What one native subscription covers.
    enum Scope: Equatable, Sendable {
        case account(String)
        /// The SDK's daemon-scoped job stream (`account.backup.job.changed`, no account). Opening it with
        /// `attended_frontend` marks this connection attended, which backup jobs require (`bus/backup_jobs/stream.rs`).
        case backupJobs
        var accountID: String? { if case .account(let id) = self { id } else { nil } }
        var topics: [String] { self == .backupJobs ? [NativeUpdateSource.backupJobTopic] : NativeUpdateSource.topics }
    }
    /// `message.received` and `group.message.received` are what the SDK journal emits for an inbound row
    /// (`bus/journal/project.rs`); without them a new message reached an open chat only through
    /// `conversation.changed`.
    static let topics = ["conversation.changed", "surface.changed", "surface.resync", "surface.rejected", "surface.rpc.conflict", "call.changed", "task.changed", "mcp.approval.request", "mcp.approval.granted", "mcp.approval.denied", "message.received", "group.message.received", "message.changed", "message.updated", "group.changed", "group.invitation", "group.state.conflict", "group.state.delivery_failed", "contact.changed", "contact.requested", "contact.accepted", "contact.declined", "contact.blocked", "account.state", transientTopic, identityChangedTopic, devicesChangedTopic, groupEventTopic]
    /// Live-only frames (typing indicators). They never invalidate read models.
    static let transientTopic = "message.transient"
    /// Direct-chat identity events whose payload the identity repository parses (see `EventFrame`).
    static let identityChangedTopic = "contact.identity_changed"
    static let devicesChangedTopic = "conversation.devices_changed"
    /// MLS group events (M2); the payload goes to `NativeMlsGroupRepository.events` and is never logged.
    static let groupEventTopic = "group.event"
    static let payloadTopics: Set<String> = [identityChangedTopic, devicesChangedTopic, groupEventTopic]
    /// The only topic the SDK accepts on a subscription without an account.
    static let backupJobTopic = "account.backup.job.changed"
    /// Consecutive resubscriptions without a delivered event before the hub reports a failure.
    static let resyncLimit = 4
    private let client: RamfluxClient
    private var scope: Scope?
    private var observers: [UUID: AsyncStream<RepositoryUpdate>.Continuation] = [:]
    private var transients: [UUID: AsyncStream<TransientFrame>.Continuation] = [:]
    private var eventSinks: [UUID: AsyncStream<EventFrame>.Continuation] = [:]
    private var subscription: EventSubscription?
    private var pump: Task<Void, Never>?
    private var epoch: UInt64 = 0
    private var resyncs = 0
    private var tail: Task<Void, Never>?
    /// The SDK is suspended for the background: observers stay registered and the subscription reopens
    /// on resume, which invalidates every observer once so each screen re-reads what changed meanwhile.
    private var suspended = false
    /// Leases that keep the subscription closed (see `unattended`); nothing opens while this is above zero.
    private var detached = 0
    public init(client: RamfluxClient) { self.client = client }
    /// Closes the native subscription before the SDK suspends; observers are kept.
    public func suspendForBackground() async {
        await serialized { hub in await hub.pause() }
    }
    /// Reopens the subscription after the SDK resumed.
    public func resumeAfterBackground() async {
        await serialized { hub in await hub.unpause() }
    }
    private func pause() async { suspended = true; resyncs = 0; await close(finishing: false) }
    private func unpause() async {
        guard suspended else { return }
        suspended = false
        if subscription == nil, detached == 0 { await open() }
    }
    /// Runs `body` while this client's subscription is not attended for an account other than `account`
    /// (nil: for any account). Core refuses app-lock calls for another account on an attended connection, so the
    /// subscription is closed (its `subscription.close` answer awaited) before `body` and reopened for the same
    /// scope afterwards, which tells every observer to reload. Nested leases share one close and one reopen.
    public func unattended<T: Sendable>(for account: String?, _ body: @Sendable () async throws -> T) async throws -> T {
        let held = LeaseMark()
        await serialized { hub in await hub.detach(for: account, held: held) }
        do {
            let value = try await body()
            await reattach(held: held)
            return value
        } catch {
            await reattach(held: held)
            throw error
        }
    }
    private func detach(for account: String?, held: LeaseMark) async {
        let attendedElsewhere = subscription != nil && scope?.accountID != nil && (account == nil || scope?.accountID != account)
        guard attendedElsewhere || detached > 0 || subscription == nil else { return }
        detached += 1; held.flag.withLock { $0 = true }
        if subscription != nil { await close(finishing: false) }
    }
    private func reattach(held: LeaseMark) async {
        await serialized { hub in
            guard held.flag.withLock({ value in let was = value; value = false; return was }) else { return }
            await hub.release()
        }
    }
    private func release() async {
        guard detached > 0 else { return }
        detached -= 1
        if detached == 0, !suspended, scope != nil, !observers.isEmpty, subscription == nil { await open() }
    }
    /// Number of live observers; for tests and diagnostics.
    public var observerCount: Int { observers.count }
    /// Registers an observer. With `transientFrames`, the observation also carries the live
    /// `message.transient` frames of the account (bounded to the newest 32).
    public func observe(account: String, transientFrames: Bool = false, eventFrames: Bool = false) async -> RepositoryObservation {
        await observe(scope: .account(account), transientFrames: transientFrames, eventFrames: eventFrames)
    }
    /// Registers an observer of backup and restore job changes while no account is open (restoring onto a
    /// new install). It ends any account observers, like observing another account does.
    public func observeBackupJobs() async -> RepositoryObservation { await observe(scope: .backupJobs, transientFrames: false, eventFrames: false) }
    private func observe(scope: Scope, transientFrames: Bool, eventFrames: Bool) async -> RepositoryObservation {
        let id = UUID()
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        let frames = transientFrames ? AsyncStream<TransientFrame>.makeStream(bufferingPolicy: .bufferingNewest(32)) : nil
        let payloads = eventFrames ? AsyncStream<EventFrame>.makeStream(bufferingPolicy: .bufferingNewest(32)) : nil
        await serialized { hub in await hub.join(id: id, scope: scope, continuation: pair.continuation, transient: frames?.continuation, events: payloads?.continuation) }
        return RepositoryObservation(stream: pair.stream, transient: frames?.stream, events: payloads?.stream, onStop: { [weak self] in await self?.remove(id) })
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
    private func join(id: UUID, scope: Scope, continuation: AsyncStream<RepositoryUpdate>.Continuation, transient: AsyncStream<TransientFrame>.Continuation?, events: AsyncStream<EventFrame>.Continuation?) async {
        if self.scope != scope { await close(finishing: true); self.scope = scope }
        observers[id] = continuation; transients[id] = transient; eventSinks[id] = events
        if subscription == nil { await open() } else { continuation.yield(.invalidated) }
    }
    private func leave(id: UUID) async {
        guard let continuation = observers.removeValue(forKey: id) else { return }
        continuation.finish(); transients.removeValue(forKey: id)?.finish(); eventSinks.removeValue(forKey: id)?.finish()
        if observers.isEmpty { await close(finishing: false); scope = nil }
    }
    private func open() async {
        guard !suspended, detached == 0, let scope, !observers.isEmpty else { return }
        do {
            try await client.resetEvents()
            let filter = try SubscriptionFilter(accountID: scope.accountID, topics: scope.topics, attendedFrontend: true)
            let opened = try await client.events(filter)
            epoch &+= 1; let current = epoch
            subscription = opened
            EventDiagnostics.note("subscription open epoch=\(current) observers=\(observers.count)")
            pump = Task { [weak self] in
                do {
                    for try await frame in opened.stream { await self?.delivered(frame, epoch: current) }
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
        if finishing { for continuation in observers.values { continuation.finish() }; observers.removeAll(); finishTransients(); resyncs = 0 }
    }
    private func delivered(_ frame: JSONValue, epoch current: UInt64) {
        guard current == epoch else { return }
        resyncs = 0
        let topic = frame["method"]?.string ?? frame["topic"]?.string
        EventDiagnostics.note("frame topic=\(topic ?? "?") epoch=\(current) observers=\(observers.count)")
        if let topic, Self.payloadTopics.contains(topic) {
            // The payload goes only to observers that asked; every observer still reloads like for any other topic.
            if !eventSinks.isEmpty, let body = frame["body"], let bytes = try? JSONEncoder().encode(body), bytes.count <= 65_536 {
                let value = EventFrame(topic: topic, body: bytes)
                for continuation in eventSinks.values { continuation.yield(value) }
            }
            broadcast(.invalidated); return
        }
        guard topic == Self.transientTopic else { broadcast(.invalidated); return }
        guard !transients.isEmpty, let body = frame["body"], let bytes = try? JSONEncoder().encode(body), bytes.count <= 65_536 else { return }
        let value = TransientFrame(topic: Self.transientTopic, body: bytes)
        for continuation in transients.values { continuation.yield(value) }
    }
    private func ended(epoch current: UInt64, failure: (any Error)?) {
        guard current == epoch else { return }
        Task { await serialized { hub in await hub.recover(epoch: current, failure: failure) } }
    }
    private func recover(epoch current: UInt64, failure: (any Error)?) async {
        guard current == epoch else { return }
        EventDiagnostics.note("subscription ended epoch=\(current) failure=\(failure.map { String(describing: type(of: $0)) } ?? "none")")
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
        observers.removeAll(); finishTransients(); scope = nil; resyncs = 0
    }
    private func finishTransients() {
        for continuation in transients.values { continuation.finish() }; transients.removeAll()
        for continuation in eventSinks.values { continuation.finish() }; eventSinks.removeAll()
    }
    deinit { subscription?.cancel(); pump?.cancel() }
}
