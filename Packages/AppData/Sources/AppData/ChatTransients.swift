// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Connects the chat's typing indicator to the shared event fan-out: each call registers one
/// observer with transient frames on the account subscription and yields the JSON bodies of its
/// `message.transient` frames. The observer leaves the fan-out when the consumer stops iterating.
public struct UpdateSourceChatTransients: ChatTransientSource {
    private let updates: NativeUpdateSource
    public init(updates: NativeUpdateSource) { self.updates = updates }
    public func transients(account: String) async -> AsyncStream<JSONValue> {
        let observation = await updates.observe(account: account, transientFrames: true)
        guard let frames = observation.transient else { await observation.stop(); return AsyncStream { $0.finish() } }
        return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            let task = Task {
                for await frame in frames where frame.topic == NativeUpdateSource.transientTopic {
                    if let body = try? JSONDecoder().decode(JSONValue.self, from: frame.body) { continuation.yield(body) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel(); Task { await observation.stop() } }
        }
    }
}
