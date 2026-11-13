// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct RetainedMutationTests {
    @Test func retryRefusalDoesNotProveAnEarlierUnknownAttemptHadNoEffect() async {
        let owner = RetainedMutation<String, String>()
        #expect(await owner.run(scope: "account", arguments: "original", operationID: "key", operation: { .failure(.outcomeUnknown) }) == .failure(.outcomeUnknown))
        #expect(await owner.run(scope: "account", arguments: "original", operationID: "key", operation: { .failure(.invalidInput) }) == .failure(.outcomeUnknown))
        #expect(await owner.snapshot(scope: "account")?.unresolved == true)
        #expect(await owner.run(scope: "account", arguments: "different", operationID: "fresh", operation: { .success("wrong") }) == .failure(.outcomeUnknown))
    }
    @Test func sendAndContactOwnersRetainExactAttemptsAfterCancelledWaiters() async {
        let dispatched = AsyncStream<Void>.makeStream(), release = DispatchSemaphore(value: 0)
        defer { release.signal(); release.signal(); dispatched.continuation.finish() }
        let transport = ProxyTransport { request in
            if request.method == "conversation.send" || request.method == "contact.add" {
                dispatched.continuation.yield(())
                guard release.wait(timeout: .now() + 5) == .success else { throw AppFailure.failed }
                throw AppFailure.outcomeUnknown
            }
            return .object([:])
        }
        let client = RamfluxClient(transport: transport), updates = NativeUpdateSource(client: client)
        let chat = NativeChatRepository(client: client, updates: updates), contacts = NativeContactsRepository(client: client, updates: updates)
        var events = dispatched.stream.makeAsyncIterator()
        let send = Task { await chat.send(account: "a", conversation: "A", text: "original", operationID: "send-key") }
        _ = await events.next(); send.cancel()
        let inFlight = await chat.sendState(account: "a", conversation: "A")
        #expect(inFlight?.operationID == "send-key"); #expect(inFlight?.text == "original"); #expect(inFlight?.unresolved == true)
        release.signal(); _ = await send.value
        #expect(await chat.sendState(account: "a", conversation: "B") == nil)
        #expect(await chat.send(account: "a", conversation: "A", text: "different", operationID: "fresh") == .failure(.outcomeUnknown))
        let add = Task { await contacts.add(account: "a", principal: "peer", operationID: "contact-key") }
        _ = await events.next(); add.cancel(); release.signal(); _ = await add.value
        #expect(await contacts.pendingMutation(account: "a") == PendingContactMutation(arguments: .add("peer"), operationID: "contact-key"))
        if case .failure(.outcomeUnknown) = await contacts.decide(account: "a", request: "r", decision: .accept, operationID: "fresh") {} else { Issue.record("Conflicting contact action was admitted") }
        #expect(transport.calls.withLock { $0.map(\.method) } == ["conversation.send", "contact.add"])
    }
}
