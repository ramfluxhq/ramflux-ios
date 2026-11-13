// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RamfluxCore
import Synchronization
public enum RepositoryUpdate: Equatable, Sendable { case invalidated, failed(AppFailure) }
/// One visible feature owns this observation. Replacement joins the previous native subscription.
public final class RepositoryObservation: Sendable {
    public let stream: AsyncStream<RepositoryUpdate>
    private let task: Task<Void, Never>?
    private let onStop: @Sendable () async -> Void
    private let stopCalled = Mutex(false)
    private let subscription: EventSubscription?
    init(subscription: EventSubscription) {
        onStop = {}; self.subscription = subscription
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); stream = pair.stream
        pair.continuation.onTermination = { _ in subscription.cancel() }
        task = Task {
            pair.continuation.yield(.invalidated)
            do {
                for try await _ in subscription.stream {
                    guard !Task.isCancelled else { break }; pair.continuation.yield(.invalidated)
                }
            } catch { if !Task.isCancelled { pair.continuation.yield(.failed(AppFailure.map(error))) } }
            pair.continuation.finish(); await subscription.stop()
        }
    }
    public init(failure: AppFailure) { onStop = {}; subscription = nil; task = nil; stream = AsyncStream { $0.yield(.failed(failure)); $0.finish() } }
    public init(stream: AsyncStream<RepositoryUpdate>, onStop: @escaping @Sendable () async -> Void = {}) { self.onStop = onStop; subscription = nil; task = nil; self.stream = stream }
    public func stop() async { task?.cancel(); subscription?.cancel(); await task?.value; await subscription?.stop(); let call = stopCalled.withLock { value in let old = value; value = true; return !old }; if call { await onStop() } }
    deinit { task?.cancel(); subscription?.cancel() }
}
public actor NativeUpdateSource {
    private let client: RamfluxClient
    private var transition: Task<RepositoryObservation, Never>?
    public init(client: RamfluxClient) { self.client = client }
    public func observe(account: String) async -> RepositoryObservation {
        let previous = transition
        let task = Task { [client] in
            if let previous { await previous.value.stop() }
            do {
                try await client.resetEvents()
                let filter = try SubscriptionFilter(accountID: account, topics: ["conversation.changed", "call.changed", "task.changed", "mcp.approval.request", "mcp.approval.granted", "mcp.approval.denied", "message.changed", "message.updated", "group.changed", "group.state.conflict", "group.state.delivery_failed", "contact.changed", "contact.requested", "contact.accepted", "contact.declined", "contact.blocked", "account.state", "account.backup.job.changed"], attendedFrontend: true)
                return RepositoryObservation(subscription: try await client.events(filter))
            } catch { return RepositoryObservation(failure: AppFailure.map(error)) }
        }
        transition = task; return await task.value
    }
    deinit { transition?.cancel() }
}
