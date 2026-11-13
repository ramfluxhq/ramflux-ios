// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// Stops both established and concurrently opening pumps before supervisor shutdown.
actor EventRegistry {
    private struct WeakSubscription: Sendable { weak var value: EventSubscription? }
    private var accepting = true
    private var opening: Task<EventSubscription, any Error>?
    private var subscriptions: [WeakSubscription] = []
    func activate() { accepting = true }
    func open(_ create: @escaping @Sendable () async throws -> EventSubscription) async throws -> EventSubscription {
        guard accepting, opening == nil else { throw BridgeError.closed }
        let task = Task { try await create() }
        opening = task
        do {
            let subscription = try await task.value
            opening = nil
            guard accepting else { await subscription.stop(); throw BridgeError.closed }
            subscriptions.removeAll { $0.value == nil }
            subscriptions.append(WeakSubscription(value: subscription))
            return subscription
        } catch { opening = nil; throw error }
    }
    func pause() async {
        accepting = false
        let established = subscriptions.compactMap(\.value)
        subscriptions.removeAll()
        if let opening, let subscription = try? await opening.value { await subscription.stop() }
        for subscription in established { await subscription.stop() }
    }
}
