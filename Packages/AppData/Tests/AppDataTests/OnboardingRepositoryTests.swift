// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import RamfluxCore
@testable import AppData
private struct CeremonyCancellation: CancellationHandle { func cancel() {} }
private final class CeremonyTransport: CoreTransport {
    let dispatched = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    let blockConfirmation: Bool
    init(blockConfirmation: Bool = false) { self.blockConfirmation = blockConfirmation }

    let requests = Mutex<[CoreRequest]>([])
    func newCancellation() throws -> any CancellationHandle { CeremonyCancellation() }
    func execute(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> JSONValue { requests.withLock { $0.append(request) }; return .object(["ok": .bool(true), "body": .object([:])]) }
    func executeSecret(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> JSONValue { throw BridgeError.invalidInput }
    func executeSecretResponse(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> SecretBytes { try reply(request) }
    func executeSecretRequestResponse(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> SecretBytes { try reply(request.request) }
    private func reply(_ request: CoreRequest) throws -> SecretBytes {
        requests.withLock { $0.append(request) }
        if request.method == "account.create.confirm", blockConfirmation {
            dispatched.continuation.yield(())
            guard release.wait(timeout: .now() + 5) == .success else { throw AppFailure.failed }
            throw AppFailure.outcomeUnknown
        }
        let body: JSONValue = switch request.method {
        case "account.create.begin": .object(["ceremony_id": .string("pending"), "expires_in_ms": .number(60_000)])
        case "account.create.show_once": .object(["phrase": .string("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima")])
        case "account.create.hidden_challenge": .object(["positions": .array([.number(3),.number(7),.number(11)])])
        case "account.create.confirm": .object(["account_id": .string("created-account"), "display_name": .string("Account")])
        default: .object([:])
        }
        let bytes = try JSONEncoder().encode(JSONValue.object(["code": .number(0), "response": .object(["ok": .bool(true), "body": body])]))
        return try bytes.withUnsafeBytes { try SecretBytes(copying: $0) }
    }
    func start() throws {}; func close() throws {}; func resume() throws {}; func resetEvents() throws {}
    func suspend() throws -> JSONValue { .object(["data_root_lock_released": .bool(true)]) }
    func subscribe(_ filter: SubscriptionFilter) throws -> any EventQueue { throw BridgeError.invalidInput }
}
@Suite(.timeLimit(.minutes(1))) struct OnboardingRepositoryTests {
    @Test func cancelledWaiterAndSuccessfulCleanupDoNotClearConfirmationFence() async {
        let transport = CeremonyTransport(blockConfirmation: true)
        defer { transport.release.signal(); transport.dispatched.continuation.finish() }
        let live = NativeOnboardingRepository(client: RamfluxClient(transport: transport))
        _ = await live.begin(name: "Account", nodeID: nil); _ = await live.showPhrase(); _ = await live.hideAndChallenge()
        let work = Task { await live.confirm(SensitiveSubmission(values: ["word1":"a", "word2":"b", "word3":"c", "passphrase":"test"])) }
        var events = transport.dispatched.stream.makeAsyncIterator(); _ = await events.next()
        work.cancel(); let cleanup = Task { await live.cancel() }; transport.release.signal()
        #expect(await work.value == .failure(.outcomeUnknown)); _ = await cleanup.value
        #expect(await live.confirmationUnresolved())
        #expect(await live.begin(name: "Fresh", nodeID: nil) == .failure(.outcomeUnknown))
        #expect(await live.beginRecovery(accountID: "account") == .failure(.outcomeUnknown))
    }
    @Test func fullCreationUsesRealProxyAndConnectionLocalUnkeyedCeremony() async {
        let transport = CeremonyTransport()
        let live = NativeOnboardingRepository(client: RamfluxClient(transport: transport))
        guard case .success = await live.begin(name: "Account", nodeID: nil) else { Issue.record("begin failed"); return }
        guard case .success(let display) = await live.showPhrase() else { Issue.record("phrase failed"); return }
        var length = 0; display.withDrawingBytes { length = $0.count }; #expect(length > 0)
        guard case .success(let positions) = await live.hideAndChallenge() else { Issue.record("challenge failed"); return }
        #expect(positions == [3,7,11])
        display.withDrawingBytes { _ in Issue.record("Hidden phrase must not render") }
        let input = SensitiveSubmission(values: ["word1":"charlie","word2":"golf","word3":"kilo","passphrase":"local test passphrase"])
        guard case .success(let account) = await live.confirm(input) else { Issue.record("confirm failed"); return }
        #expect(account.id == "created-account")
        #expect(transport.requests.withLock { $0.allSatisfy { $0.operationID == nil } })
        #expect(transport.requests.withLock { $0.map(\.method) } == ["account.create.begin","account.create.show_once","account.create.hidden_challenge","account.create.confirm"])
    }
}
