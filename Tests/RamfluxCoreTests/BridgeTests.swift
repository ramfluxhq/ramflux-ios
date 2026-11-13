// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import Security
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
    private func frame(_ secret: SecretBytes) throws -> JSONValue {
        try secret.consume { bytes in
            let value = try JSONValue.decode(Data(bytes))
            return value["response"] ?? value
        }
    }
    private func requestBytes() -> Data {
        var bytes = [CChar](repeating: 0, count: CoreLimits.frameBytes)
        let count = rf_fixture_copy_request(&bytes, bytes.count)
        return bytes.withUnsafeBytes { Data($0.prefix(count)) }
    }
    private func awaitFixture(_ condition: @Sendable () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline { await Task.yield() }
        try #require(condition(), "Fixture did not reach its semantic barrier")
    }
    @Test func negotiatedPolicyMustExactlyMatchPinnedFlagsAndInventory() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/sdk-method-policy.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let original = try #require(manifest["methods"] as? [[String: Any]])
        for kind in 0..<7 {
            rf_fixture_reset()
            var rows = original
            switch kind {
            case 0: rows[0]["secret_input"] = !(rows[0]["secret_input"] as? Bool ?? false)
            case 1: rows[0]["secret_output"] = !(rows[0]["secret_output"] as? Bool ?? false)
            case 2: rows[0]["show_once"] = !(rows[0]["show_once"] as? Bool ?? false)
            case 3: rows[0]["capability"] = "wrong"
            case 4: rows.removeLast()
            case 5: rows.append(original[0])
            default: rows[0].removeValue(forKey: "secret_output")
            }
            manifest["methods"] = rows
            let json = try JSONSerialization.data(withJSONObject: manifest)
            rf_fixture_set_policy(String(decoding: json, as: UTF8.self))
            #expect(throws: BridgeError.incompatibleABI) { try NativeCore(dataRoot: URL(fileURLWithPath: "/unused-fixture-root")) }
            #expect(rf_fixture_opens() == 0)
        }
        rf_fixture_reset(); rf_fixture_set_policy("{}")
        #expect(throws: BridgeError.incompatibleABI) { try NativeCore(dataRoot: URL(fileURLWithPath: "/unused-fixture-root")) }
    }
    @Test func subscriptionSlotRemainsFencedUntilCloseAcknowledged() async throws {
        rf_fixture_reset(); let (core, client) = try await open()
        let filter = try SubscriptionFilter(topics: ["message"])
        let subscription = try await client.events(filter)
        rf_fixture_set_release_busy(2)
        rf_fixture_set_ack_pending(1)
        let stop = Task { await subscription.stop() }
        try await awaitFixture { rf_fixture_ack_polls() > 0 }
        #expect(throws: BridgeError.invalidInput) { try core.resetEvents() }
        #expect(throws: BridgeError.invalidInput) { try core.subscribe(filter) }
        rf_fixture_set_ack_pending(0)
        await stop.value
        try core.resetEvents()
        let next = try await client.events(filter)
        await next.stop(); try await client.close()
    }
    @Test func blockingOpenAndCloseDoNotHoldStateMutex() async throws {
        rf_fixture_reset()
        let core = try NativeCore(dataRoot: URL(fileURLWithPath: "/unused-fixture-root"))
        rf_fixture_set_block_open(1)
        let opening = Task.detached { try core.start() }
        try await awaitFixture { rf_fixture_io_entered() == 1 }
        #expect(throws: BridgeError.closed) { try core.currentHandle() }
        #expect(throws: BridgeError.closed) { try core.start() }
        #expect(rf_fixture_io_waiting() == 1)
        rf_fixture_unblock_io(); try await opening.value
        let queue = try core.subscribe(SubscriptionFilter(topics: ["message"]))
        rf_fixture_set_block_close(1)
        let closing = Task.detached { try core.close() }
        try await awaitFixture { rf_fixture_closes() > 0 }
        queue.cancel()
        #expect(throws: BridgeError.closed) { try core.currentHandle() }
        #expect(throws: BridgeError.lockStillHeld) { try core.close() }
        #expect(rf_fixture_io_waiting() == 1)
        rf_fixture_unblock_io(); try await closing.value
        try core.start(); try core.close()
    }
    @Test func terminalShutdownErrorIsReportedAndHandleReleasedForReopen() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let lifecycle = PhoneLifecycle(client: client, dataRoot: URL(fileURLWithPath: "/unused-fixture-root"))
        try await lifecycle.foreground()
        rf_fixture_set_close_code(8)
        do { try await lifecycle.close(); Issue.record("Expected terminal shutdown failure") }
        catch let failure as CoreFailure { #expect(failure.rawCode == 8); #expect(failure.writerReleaseConfirmed) }
        #expect(rf_fixture_client_releases() == 1)
        #expect(await lifecycle.state == .stopped)
        rf_fixture_set_close_code(0)
        try await lifecycle.foreground(); try await lifecycle.close()
        #expect(rf_fixture_opens() == 2)
    }
    @Test func nativeRequestPreservesIdentityAndReleasesBuffers() async throws {
        rf_fixture_reset()
        let (_, client) = try await open()
        let response = try frame(await SDKProxy(client: client).accountList(context: context()))
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
        let task = Task { try await client.executeSecretRequestResponse(SecretRequest(request: request, fields: [:])) }
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
        #expect(throws: CoreFailure.self) { try core.executeSecretResponse(request, cancellation: cancellation) }
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
    @Test func sealedNativeCompletionExtractsOnlyAllowlistedVaultRefusals() async throws {
        for reason in ["vault_permission", "vault_locked", "vault_missing", "vault_corrupt", "vault_busy", "vault_primary_unavailable"] {
            rf_fixture_reset()
            let terminal = "{\"code\":16,\"response\":{\"error\":{\"reason_code\":\"\(reason)\",\"message\":\"private-test-text\"}}}"
            rf_fixture_set_terminal(terminal)
            let (_, client) = try await open()
            do { _ = try await SDKProxy(client: client).accountList(context: context()); Issue.record("Expected sealed native refusal") }
            catch let failure as CoreFailure {
                #expect(failure.rawCode == 16); #expect(failure.reasonCode == reason)
                #expect(failure.response == nil); #expect(failure.sealedResponse != nil)
                #expect(!String(describing: failure).contains("private-test-text"))
                failure.sealedResponse?.erase()
            }
            #expect(rf_fixture_live_buffers() == 0)
            try await client.close()
        }
    }
    @Test func businessFailurePreservesSDKErrorFrame() async throws {
        rf_fixture_reset()
        rf_fixture_set_terminal("{\"code\":23,\"response\":{\"error\":{\"reason_code\":\"schema_reset_required\",\"details\":{\"generation\":\"18446744073709551615\"}}}}")
        let (_, client) = try await open()
        do { _ = try await SDKProxy(client: client).accountList(context: context()); Issue.record("Schema error was lost") }
        catch let error as CoreFailure {
            #expect(error.code == .schemaResetRequired)
            let preserved = try #require(error.sealedResponse)
            let response = try frame(preserved)
            #expect(response["error"]?["reason_code"] == .string("schema_reset_required"))
            #expect(response["error"]?["details"]?["generation"] == .string("18446744073709551615"))
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
        await #expect(throws: BridgeError.lockStillHeld) { try await lifecycle.background() }
        #expect(await lifecycle.state == .failed)
        await #expect(throws: BridgeError.lockStillHeld) { try await lifecycle.foreground() }
        rf_fixture_set_close_code(0)
        try await lifecycle.close()
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
        rf_fixture_reset(); rf_fixture_set_methods("[\"account.list\"]")
        #expect(throws: BridgeError.incompatibleABI) { try NativeCore(dataRoot: URL(fileURLWithPath: "/unused-fixture-root")) }
        rf_fixture_reset()
        let (_, client) = try await open()
        let proxy = SDKProxy(client: client)
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
        let deep = Data((String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129)).utf8)
        #expect(throws: BridgeError.invalidResponse) { try JSONValue.decode(deep) }
        let wide = Data(("[" + Array(repeating: "0", count: 4097).joined(separator: ",") + "]").utf8)
        let decoded = try JSONValue.decode(wide)
        #expect(throws: BridgeError.invalidResponse) { try decoded.encodedRequest() }
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
        #expect(try await iterator.next() == nil)
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

    @Test func subscriptionTokenLivesUntilStopAndReleasesOnce() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let subscription = try await client.events(SubscriptionFilter(accountID: "account", topics: ["message"]))
        #expect(rf_fixture_subscription_releases() == 0)
        rf_fixture_set_event("{\"body\":{\"event\":\"delivered\"}}")
        var iterator = subscription.stream.makeAsyncIterator()
        #expect(try await iterator.next()?["body"]?["event"] == .string("delivered"))
        await subscription.stop(); await subscription.stop()
        #expect(rf_fixture_subscription_cancels() == 1)
        #expect(rf_fixture_subscription_releases() == 1)
        #expect(try await iterator.next() == nil)
        try await client.close()
    }
    @Test func overflowResetAndFailedOpenPermitResubscription() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let filter = try SubscriptionFilter(accountID: "account", topics: ["message"])
        let first = try await client.events(filter)
        rf_fixture_set_event_status(27)
        var iterator = first.stream.makeAsyncIterator()
        await #expect(throws: BridgeError.resyncRequired) { try await iterator.next() }
        try await client.resetEvents()
        #expect(rf_fixture_resets() == 1)
        rf_fixture_set_terminal("{\"code\":15,\"effects\":\"none\"}")
        await #expect(throws: CoreFailure.self) { try await client.events(filter) }
        rf_fixture_set_terminal("{\"code\":0,\"response\":{\"body\":{}}}")
        let second = try await client.events(filter)
        rf_fixture_set_event("{\"body\":{\"event\":\"resumed\"}}")
        var next = second.stream.makeAsyncIterator()
        #expect(try await next.next()?["body"]?["event"] == .string("resumed"))
        await second.stop(); try await client.close()
    }
    @Test func busyOpenRetriesAndTimedOutCloseRetainsWriterHandle() async throws {
        rf_fixture_reset(); rf_fixture_set_open_code(18)
        let core = try NativeCore(dataRoot: URL(fileURLWithPath: "/unused-fixture-root"))
        let client = RamfluxClient(transport: core)
        let lifecycle = PhoneLifecycle(client: client, dataRoot: URL(fileURLWithPath: "/unused-fixture-root"))
        await #expect(throws: CoreFailure.self) { try await lifecycle.foreground() }
        #expect(await lifecycle.state == .stopped)
        try await lifecycle.foreground()
        #expect(rf_fixture_opens() == 2)
        rf_fixture_set_close_code(10)
        await #expect(throws: BridgeError.lockStillHeld) { try await lifecycle.background() }
        #expect(throws: BridgeError.closed) { try core.start() }
        #expect(rf_fixture_opens() == 2)
        rf_fixture_set_close_code(24)
        await #expect(throws: BridgeError.lockStillHeld) { try await lifecycle.close() }
        #expect(throws: BridgeError.closed) { try core.start() }
        #expect(rf_fixture_opens() == 2)
        rf_fixture_set_close_code(0)
        try await lifecycle.close()
        #expect(rf_fixture_closes() == 3)
        try await lifecycle.foreground()
        #expect(rf_fixture_opens() == 3)
        try await lifecycle.close()
    }
    @Test func showOnceUsesSealedBytesAndHideErasesOnlyBridgeCopy() async throws {
        rf_fixture_reset(); let (core, client) = try await open()
        let ceremony = AccountCeremony(proxy: SDKProxy(client: client), kind: .creation)
        let begin = try await ceremony.begin(context: context(mutation: true), body: .object([:]))
        begin.erase()
        rf_fixture_set_terminal("{\"code\":0,\"response\":{\"body\":{\"phrase\":\"sentinel mnemonic\"}}}")
        rf_fixture_set_secret_terminal(1)
        let phrase: SecretBytes = try await ceremony.showPhraseOnce(context: context(mutation: true))
        #expect(!phrase.isErased)
        #expect(rf_fixture_live_buffers() == 0)
        let plain = try CoreRequest(method: "account.create.show_once", sdkAPI: "account",
            operationID: OperationID("never-plain"), deadlineUnixMilliseconds: context().deadlineUnixMilliseconds)
        #expect(throws: BridgeError.invalidInput) { try core.execute(plain, cancellation: core.newCancellation()) }
        try await ceremony.hidePhrase()
        #expect(phrase.isErased)
        #expect(throws: BridgeError.secretConsumed) { try phrase.consume { _ in () } }
        #expect(SDKOperation.accountCreateShowOnce.showOnce)
        #expect(SDKOperation.accountCreateShowOnce.requiresSecureOutput)
        try await client.close()
    }
    @Test func largeSuccessfulMutationCompletionIsNotUnknown() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let row = JSONValue.object(Dictionary(uniqueKeysWithValues: (0..<40).map { ("k\($0)", .string("v")) }))
        let terminal = JSONValue.object(["code": .number(0), "response": .object(["body": .object(["rows": .array(Array(repeating: row, count: 2000))])])])
        let encoded = try terminal.encoded()
        #expect(encoded.count < CoreLimits.frameBytes)
        rf_fixture_set_terminal(String(decoding: encoded, as: UTF8.self))
        let response = try await SDKProxy(client: client).accountBackupCancel(context: context(mutation: true))
        let body = try #require(response["body"])
        let value = try #require(body["rows"])
        if case .array(let rows) = value { #expect(rows.count == 2000) }
        else { Issue.record("Successful rows lost") }
        try await client.close()
    }
    @Test func generatedMethodsExactlyMatchNegotiatedInventoryAndSecretFlags() async throws {
        rf_fixture_reset(); let (core, client) = try await open()
        #expect(Set(SDKOperation.allCases.map(\.rawValue)) == core.methods)
        #expect(SDKOperation.devicePairJoin.requiresSecureInput)
        #expect(SDKOperation.accountCustodyShowOnce.showOnce)
        try await client.close()
    }
    @Test func streamOwnsSubscriptionAfterHandleIsDropped() async throws {
        rf_fixture_reset(); let (_, client) = try await open()
        let stream = try await client.events(SubscriptionFilter(accountID: "account", topics: ["message"])).stream
        #expect(rf_fixture_subscription_releases() == 0)
        rf_fixture_set_event("{\"body\":{\"event\":\"still-live\"}}")
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next()?["body"]?["event"] == .string("still-live"))
        try await client.close()
        #expect(try await iterator.next() == nil)
        #expect(rf_fixture_subscription_releases() == 1)
    }
    @Test func subscriptionOpeningHasReservedWorkerCredit() async throws {
        rf_fixture_reset(); rf_fixture_set_pending(1)
        let (_, client) = try await open()
        let request = try CoreRequest(method: "daemon.status", sdkAPI: "daemon",
            deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 10_000)
        let tasks = (0..<4).map { _ in Task { try await client.execute(request) } }
        let deadline = ContinuousClock.now + .seconds(2)
        while rf_fixture_submissions() < 4 && ContinuousClock.now < deadline { await Task.yield() }
        #expect(rf_fixture_submissions() == 4)
        let subscription = try await client.events(SubscriptionFilter(accountID: "account", topics: ["message"]))
        #expect(rf_fixture_submissions() == 5)
        await subscription.stop()
        for task in tasks { task.cancel(); _ = try? await task.value }
        try await client.close()
    }
    @Test func nestedStorageFilesAreProtectedAndSymlinksRefused() throws {
        #if os(iOS)
        let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let root = try AppStorage.prepare(applicationSupport: support)
        let owned = root.appendingPathComponent(UUID().uuidString)
        #else
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let owned = root
        #endif
        let nested = owned.appendingPathComponent("account/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: owned) }
        let database = nested.appendingPathComponent("store.db")
        try Data([0]).write(to: database)
        try AppStorage.protectDatabaseFiles(in: root)
        let attributes = try FileManager.default.attributesOfItem(atPath: database.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #if os(iOS)
        #expect(attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
        #endif
        try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("link"), withDestinationURL: database)
        #expect(throws: BridgeError.unsafeStoragePath) { try AppStorage.protectDatabaseFiles(in: root) }
    }
    private final class MemoryKeychain: KeychainAccess {
        let entries = Mutex([String: Data]())
        let policyValid = Mutex(true)
        private func fields(_ query: CFDictionary) -> [String: Any] { query as! [String: Any] }
        private func inspect(_ values: [String: Any]) {
            let valid = values[kSecUseDataProtectionKeychain as String] as? Bool == true
                && values[kSecAttrSynchronizable as String] as? Bool == false
            policyValid.withLock { $0 = $0 && valid }
        }
        func add(_ query: CFDictionary) -> OSStatus {
            let values = fields(query); inspect(values)
            guard let account = values[kSecAttrAccount as String] as? String,
                  let input = values[kSecValueData as String] as? Data else { return errSecParam }
            policyValid.withLock { $0 = $0 && (values[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String) }
            let copy = input.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
            return entries.withLock { if $0[account] != nil { return errSecDuplicateItem }; $0[account] = copy; return errSecSuccess }
        }
        func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
            let values = fields(query); inspect(values)
            guard let account = values[kSecAttrAccount as String] as? String,
                  let input = fields(attributes)[kSecValueData as String] as? Data else { return errSecParam }
            let copy = input.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
            entries.withLock { $0[account] = copy }; return errSecSuccess
        }
        func copy(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
            let values = fields(query); inspect(values)
            guard let account = values[kSecAttrAccount as String] as? String,
                  let data = entries.withLock({ $0[account] }) else { return errSecItemNotFound }
            if let result { result.pointee = data as CFData }
            return errSecSuccess
        }
        func delete(_ query: CFDictionary) -> OSStatus {
            let values = fields(query); inspect(values)
            guard let account = values[kSecAttrAccount as String] as? String else { return errSecParam }
            return entries.withLock { $0.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess }
        }
    }
    @Test func keychainStoreLoadUpdateAndOrphanPolicy() async throws {
        let backend = MemoryKeychain()
        let vault = KeychainVault(service: "unit-test", keychain: backend)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let database = temp.appendingPathComponent("db")
        try Data([0]).write(to: database)
        let input = try secret("first")
        try await vault.store(input, account: "account")
        #expect(input.isErased)
        try await vault.store(secret("second"), account: "account")
        let loaded = try await vault.load(account: "account", existingDatabase: database)
        let matches = try loaded.consume { Array($0) == Array("second".utf8) }
        #expect(matches)
        #expect(loaded.isErased)
        try FileManager.default.removeItem(at: database)
        await #expect(throws: BridgeError.orphanedVault) { try await vault.load(account: "account", existingDatabase: database) }
        try await vault.remove(account: "account")
        await #expect(throws: BridgeError.missingVault) { try await vault.load(account: "account", existingDatabase: database) }
        #expect(backend.policyValid.withLock { $0 })
    }

    @Test func secretRequestUsesFrameLimitAndExactAdmissionSize() throws {
        let context = try context(mutation: true)
        let request = try CoreRequest(method: "account.backup.cancel", sdkAPI: "account", operationID: context.operationID,
            body: .object(["metadata": .string(String(repeating: "x", count: 25_000))]), deadlineUnixMilliseconds: context.deadlineUnixMilliseconds)
        let secret = try SecretRequest(request: request, fields: [:])
        #expect(secret.json.byteCount > 25_000)
        #expect(secret.json.byteCount < CoreLimits.frameBytes)
        secret.json.erase()
    }

}

struct EventGenerationTests {
    @Test func exactGenerationAndAccountAreBothRequired() throws {
        let identity = try EventIdentity(snapshot: .object(["subscription_generation": .string("18446744073709551615")]), accountID: "account")
        #expect(identity.accepts(.object(["subscription_generation": .string("18446744073709551615"), "account_id": .string("account")])))
        #expect(!identity.accepts(.object(["subscription_generation": .string("18446744073709551614"), "account_id": .string("account")])))
        #expect(!identity.accepts(.object(["subscription_generation": .string("18446744073709551615"), "account_id": .string("other")])))
        for value in [JSONValue.string("0"), .string("01"), .number(1), .string("18446744073709551616")] {
            #expect(throws: BridgeError.invalidResponse) { try EventIdentity(snapshot: .object(["subscription_generation": value]), accountID: nil) }
        }
    }
}

extension BridgeTests {
    @Test func nativeQueueDropsStaleGenerationAndWrongAccount() async throws {
        rf_fixture_reset(); let (core, client) = try await open()
        let filter = try SubscriptionFilter(accountID: "account", topics: ["message"])
        let first = try core.subscribe(filter)
        rf_fixture_set_event("{\"subscription_generation\":\"0\",\"account_id\":\"account\",\"body\":{\"value\":\"stale\"}}")
        #expect(try first.poll().isEmpty)
        rf_fixture_set_event("{\"subscription_generation\":\"1\",\"account_id\":\"other\",\"body\":{\"value\":\"wrong-account\"}}")
        #expect(try first.poll().isEmpty)
        rf_fixture_set_event("{\"subscription_generation\":\"1\",\"account_id\":\"account\",\"body\":{\"value\":\"current\"}}")
        #expect(try first.poll().first?["body"]?["value"] == .string("current"))
        try first.finish(); try core.resetEvents()
        let next = try core.subscribe(filter)
        rf_fixture_set_event("{\"subscription_generation\":\"1\",\"account_id\":\"account\",\"body\":{\"value\":\"old-open\"}}")
        #expect(try next.poll().isEmpty)
        rf_fixture_set_event("{\"subscription_generation\":\"2\",\"account_id\":\"account\",\"body\":{\"value\":\"new-open\"}}")
        #expect(try next.poll().first?["body"]?["value"] == .string("new-open"))
        try next.finish(); try await client.close()
        #expect(rf_fixture_live_buffers() == 0)
    }
}
