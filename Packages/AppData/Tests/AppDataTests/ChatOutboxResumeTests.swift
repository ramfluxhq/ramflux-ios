// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
@testable import AppData

@Suite(.timeLimit(.minutes(1))) struct ChatOutboxResumeTests {
    private func entry(_ id: String) -> OutboxEntry { OutboxEntry(operationID: id, text: "hello", created: 1, state: .queued) }

    /// A send that fails because the account or the SDK closed under it (a lock, the scene going to the
    /// background) stays queued for the flush after the next unlock.
    @Test func aSendInterruptedByALockOrAClosedSDKStaysQueued() async {
        for failure: AppFailure in [.locked, .sdkUnavailable] {
            let outbox = ChatOutbox()
            await outbox.enqueue("a", "c", entry: entry("op"))
            let admitted = await outbox.flush("a", "c") { _ in .failure(failure) }
            #expect(admitted.isEmpty)
            #expect(await outbox.entries("a", "c").map(\.state) == [.queued])
            #expect(await outbox.pendingConversations("a") == ["c"])
        }
    }

    /// A flush stuck on a send the closed SDK never answers does not block the flush after unlock.
    @Test func aSealReleasesAFlushStuckInFlight() async {
        let outbox = ChatOutbox()
        await outbox.enqueue("a", "c", entry: entry("op"))
        let gate = AsyncStream<Void>.makeStream()
        let stuck = Task { await outbox.flush("a", "c") { _ in for await _ in gate.stream {}; return .failure(.offline) } }
        var waited = 0
        while await outbox.entries("a", "c").first?.state != .sending && waited < 200 { try? await Task.sleep(for: .milliseconds(5)); waited += 1 }
        await outbox.seal("a")
        // After unlock (here without a vault, so the queue restarts empty) a new flush runs at once.
        await outbox.enqueue("a", "c", entry: entry("next"))
        let resumed = await outbox.flush("a", "c") { entry in .success(SendOutcome(messageID: "m-" + entry.operationID, state: .submitted)) }
        #expect(resumed.map(\.messageID) == ["m-next"])
        gate.continuation.finish(); _ = await stuck.value
        #expect(await outbox.entries("a", "c").isEmpty)
    }
}
