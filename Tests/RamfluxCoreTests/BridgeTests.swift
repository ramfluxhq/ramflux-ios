// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import Synchronization
import CABIFixture
@testable import RamfluxCore

@Suite(.serialized, .timeLimit(.minutes(1)))
struct BridgeTests {
    private func context(mutation: Bool = false) throws -> RequestContext {
        RequestContext(accountID: "account", operationID: mutation ? try OperationID("stable-operation") : nil,
                       deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 5_000)
    }
    private func open() async throws -> (NativeCore, RamfluxClient) {
        let core = try NativeCore(dataRoot: URL(fileURLWithPath: "/unused-fixture-root"))
        let client = RamfluxClient(transport: core); try await client.start(); return (core, client)
    }
    private func secret(_ text: String) throws -> SecretBytes {
        try Array(text.utf8).withUnsafeBytes { try SecretBytes(copying: $0) }
    }
    private func requestBytes() -> Data {
        var bytes = [CChar](repeating: 0, count: CoreLimits.frameBytes)
        let count = rf_fixture_copy_request(&bytes, bytes.count)
        return bytes.withUnsafeBytes { Data($0.prefix(count)) }
    }
    @Test func nativeRequestPreservesIdentityAndReleasesBuffers() async throws {
        rf_fixture_reset()
        let (_, client) = try await open()
        let response = try await SDKProxy(client: client).accountList(context: context())
        #expect(response["kind"] == .string("response"))
        let request = try JSONValue.decode(requestBytes())
        #expect(request["account_id"] == .string("account"))
        #expect(request["method"] == .string("account.list"))
        #expect(rf_fixture_submissions() == 1)
        #expect(rf_fixture_releases() == 1)
        #expect(rf_fixture_live_buffers() == 0)
        try await client.close()
    }
    @Test func cancellationAfterSubmissionRetainsUnknownEffectAndOperationID() async throws {
        rf_fixture_reset(); rf_fixture_set_pending(1)
        let (_, client) = try await open()
        let request = try CoreRequest(method: "account.unlock", sdkAPI: "account", operationID: OperationID("stable-operation"),
            deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 5_000)
        let task = Task { try await client.execute(request) }
        // Semantic barrier: wait for observed C submission, with a fixed wall-clock deadline.
        let deadline = ContinuousClock.now + .seconds(2)
        while rf_fixture_submissions() == 0 && ContinuousClock.now < deadline { await Task.yield() }
        #expect(rf_fixture_submissions() == 1)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled waiter unexpectedly succeeded") }
        catch let failure as CoreFailure {
            #expect(failure.effect == .unknown)
            #expect(failure.operationID == "stable-operation")
        }
        #expect(rf_fixture_submissions() == 1)
        #expect(rf_fixture_cancellations() >= 1)
        #expect(rf_fixture_releases() == 1)
        try await client.close()
    }
    @Test func preCancelledHandleProvesNoSubmission() async throws {
        rf_fixture_reset(); let (core, client) = try await open()
        let cancellation = try core.newCancellation(); cancellation.cancel()
        let request = try CoreRequest(method: "account.list", sdkAPI: "account",
            deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 5_000)
        #expect(throws: CoreFailure.self) { try core.execute(request, cancellation: cancellation) }
        #expect(rf_fixture_submissions() == 0)
        try await client.close()
    }
    @Test func secretRequestEscapesAndConsumesItsInputs() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let passphrase = try secret("a\"b\\c\n")
        _ = try await SDKProxy(client: client).accountUnlock(context: context(mutation: true), secrets: ["passphrase": .text(passphrase)])
        let decoded = try JSONValue.decode(requestBytes())
        #expect(decoded["body"]?["passphrase"] == .string("a\"b\\c\n"))
        #expect(throws: BridgeError.secretConsumed) { try passphrase.consume { _ in () } }
        #expect(String(describing: passphrase) == "SecretBytes")
        try await client.close()
    }
    @Test func businessFailurePreservesSDKErrorFrame() async throws {
        rf_fixture_reset()
        rf_fixture_set_terminal("{\"code\":23,\"response\":{\"error\":{\"reason_code\":\"schema_reset_required\",\"details\":{\"generation\":\"18446744073709551615\"}}}}")
        let (_, client) = try await open()
        do { _ = try await SDKProxy(client: client).accountList(context: context()); Issue.record("Schema error was lost") }
        catch let error as CoreFailure {
            #expect(error.code == .schemaResetRequired)
            #expect(error.reasonCode == "schema_reset_required")
            #expect(error.response?["error"]?["details"]?["generation"] == .string("18446744073709551615"))
        }
        #expect(rf_fixture_live_buffers() == 0)
        try await client.close()
    }
    @Test func eventOverflowRequiresResyncAndDoesNotConsumeCompletions() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let subscription = try await client.events(SubscriptionFilter(topics: ["messages"]))
        rf_fixture_set_event_status(27)
        var iterator = subscription.stream.makeAsyncIterator()
        await #expect(throws: BridgeError.resyncRequired) { try await iterator.next() }
        _ = try await SDKProxy(client: client).accountList(context: context())
        await subscription.stop(); try await client.close()
    }
    @Test func failedSuspendDoesNotAuthorizeReplacementWriter() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let lifecycle = PhoneLifecycle(client: client, dataRoot: URL(fileURLWithPath: "/unused-fixture-root"))
        try await lifecycle.foreground(); rf_fixture_set_close_code(10)
        await #expect(throws: CoreFailure.self) { try await lifecycle.background() }
        #expect(await lifecycle.state == .failed)
        await #expect(throws: BridgeError.lockStillHeld) { try await lifecycle.foreground() }
        rf_fixture_set_close_code(0)
    }
    @Test func ceremonyRequiresHideAndAllowsOneConfirmationAttempt() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let ceremony = AccountCeremony(proxy: SDKProxy(client: client), kind: .creation)
        _ = try await ceremony.begin(context: context(mutation: true), body: .object(["display_name": .string("Alex")]))
        let phrase = try await ceremony.showPhraseOnce(context: context(mutation: true))
        await #expect(throws: BridgeError.invalidCeremonyState) { try await ceremony.challenge(context: context()) }
        try await ceremony.hidePhrase()
        #expect(throws: BridgeError.secretConsumed) { try phrase.consume { _ in () } }
        _ = try await ceremony.challenge(context: context())
        let fields: [String: SecretField] = ["words": .words([try secret("one"), try secret("two"), try secret("three")]),
                                           "passphrase": .text(try secret("passphrase"))]
        _ = try await ceremony.confirm(context: context(mutation: true), fields: fields)
        #expect(await ceremony.state == .finished)
        await #expect(throws: BridgeError.invalidCeremonyState) { try await ceremony.confirm(context: context(mutation: true), fields: [:]) }
        try await client.close()
    }
    @Test func unavailableCapabilityAndMissingOperationKeyRefuseBeforeEffects() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let proxy = SDKProxy(client: client)
        await #expect(throws: CoreFailure.self) { try await proxy.groupList(context: context()) }
        await #expect(throws: BridgeError.invalidInput) { try await proxy.contactBlock(context: context()) }
        #expect(rf_fixture_submissions() == 0)
        try await client.close()
    }
    @Test func appStorageRejectsSymlinksAndExcludesDirectoryBackup() throws {
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = try AppStorage.prepare(applicationSupport: temp)
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let link = temp.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temp)
        #expect(throws: BridgeError.unsafeStoragePath) { try AppStorage.prepare(applicationSupport: link) }
    }
    @Test func exactJournalCursorAndParserLimits() throws {
        let filter = try SubscriptionFilter(topics: ["message"], afterSequence: "18446744073709551615")
        let encoded = try filter.body.encoded()
        #expect(String(decoding: encoded, as: UTF8.self).contains("18446744073709551615"))
        #expect(try JSONValue.decode(encoded)["since_seq"] == .unsigned(UInt64.max))
        let deep = Data((String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)).utf8)
        #expect(throws: BridgeError.invalidResponse) { try JSONValue.decode(deep) }
        let wide = Data(("[" + Array(repeating: "0", count: 4097).joined(separator: ",") + "]").utf8)
        #expect(throws: BridgeError.invalidResponse) { try JSONValue.decode(wide) }
    }
    @Test func deferredFeaturesReturnTypedUnavailableWithoutNativeCalls() async throws {
        rf_fixture_reset()
        let unavailable = UnavailableFeatures()
        await #expect(throws: UnavailableCapability.localSearch) { try await unavailable.search(query: "query", context: context()) }
        await #expect(throws: UnavailableCapability.agentConfiguration) { try await unavailable.createAgent(configuration: .object([:]), context: context(mutation: true)) }
        await #expect(throws: UnavailableCapability.strangerReporting) { try await unavailable.reportStranger(conversationID: "conversation", report: .object([:]), context: context(mutation: true)) }
        #expect(rf_fixture_submissions() == 0)
    }
    private final class BurstQueue: EventQueue {
        let initialSnapshot: JSONValue = .object(["snapshot": .bool(true)])
        let polls = Mutex(0)
        private let cancelled = Mutex(false)
        let value: JSONValue
        init(value: JSONValue) { self.value = value }
        func poll() throws -> [JSONValue] {
            guard !cancelled.withLock({ $0 }) else { throw BridgeError.closed }
            polls.withLock { $0 += 1 }
            return [value]
        }
        func cancel() { cancelled.withLock { $0 = true } }
    }
    @Test func streamCountAndByteOverflowAreTerminal() async throws {
        for (capacity, value) in [(1, JSONValue.string("event")), (64, .string(String(repeating: "x", count: 900_000)))] {
            let queue = BurstQueue(value: value)
            let subscription = EventSubscription(queue: queue, capacity: capacity)
            #expect(subscription.initialSnapshot["snapshot"] == .bool(true))
            let deadline = ContinuousClock.now + .seconds(2)
            while queue.polls.withLock({ $0 }) < (capacity == 1 ? 2 : 5) && ContinuousClock.now < deadline { await Task.yield() }
            // The producer has exhausted either count or byte credit without a consumer.
            await subscription.stop()
            var iterator = subscription.stream.makeAsyncIterator()
            var received = 0
            do {
                while try await iterator.next() != nil { received += 1 }
                Issue.record("Overflow ended without a resync error")
            } catch let error as BridgeError { #expect(error == .resyncRequired) }
            #expect(received <= (capacity == 1 ? 1 : 4))
        }
    }

    @Test func descriptorSkewAndMalformedCompletionDoNotClaimSuccess() async throws {
        rf_fixture_reset()
        #expect(throws: BridgeError.incompatibleABI) {
            try NativeCore(dataRoot: URL(fileURLWithPath: "/unused-fixture-root"), expectedDescriptorFingerprint: String(repeating: "1", count: 64))
        }
        let (_, client) = try await open()
        rf_fixture_set_terminal("{not-json}")
        do { _ = try await SDKProxy(client: client).accountList(context: context(mutation: true)); Issue.record("Malformed completion was accepted") }
        catch let failure as CoreFailure {
            #expect(failure.effect == .unknown)
            #expect(failure.operationID == "stable-operation")
        }
        #expect(rf_fixture_releases() == 1)
        #expect(rf_fixture_live_buffers() == 0)
        try await client.close()
    }

    @Test func closeJoinsEventPumpBeforeClosingSupervisor() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let subscription = try await client.events(SubscriptionFilter(accountID: "account", topics: ["messages"]))
        try await client.close()
        var iterator = subscription.stream.makeAsyncIterator()
        await #expect(throws: BridgeError.closed) { try await iterator.next() }
        #expect(rf_fixture_live_buffers() == 0)
    }

    @Test func ceremonyRejectsReentrantStepsUntilReply() async throws {
        rf_fixture_reset(); rf_fixture_set_pending(1)
        let (_, client) = try await open()
        let ceremony = AccountCeremony(proxy: SDKProxy(client: client), kind: .creation)
        let task = Task { try await ceremony.begin(context: context(mutation: true), body: .object([:])) }
        let deadline = ContinuousClock.now + .seconds(2)
        while rf_fixture_submissions() == 0 && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await ceremony.state == .beginning)
        await #expect(throws: BridgeError.invalidCeremonyState) { try await ceremony.showPhraseOnce(context: context(mutation: true)) }
        #expect(rf_fixture_submissions() == 1)
        rf_fixture_set_pending(0)
        _ = try await task.value
        #expect(await ceremony.state == .pending)
        try await ceremony.cancel(context: context(mutation: true))
        try await client.close()
    }

    @Test func failedCeremonyCancelDoesNotClaimRemoteCancellation() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let ceremony = AccountCeremony(proxy: SDKProxy(client: client), kind: .creation)
        _ = try await ceremony.begin(context: context(mutation: true), body: .object([:]))
        rf_fixture_set_terminal("{\"code\":10,\"effects\":\"unknown\"}")
        await #expect(throws: CoreFailure.self) { try await ceremony.cancel(context: context(mutation: true)) }
        #expect(await ceremony.state == .failed)
        try await client.close()
    }

}
