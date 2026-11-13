// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import RamfluxCore
@testable import AppData
private struct CeremonyCancellation: CancellationHandle { func cancel() {} }
private final class CeremonyTransport: CoreTransport {
    let requests = Mutex<[CoreRequest]>([])
    func newCancellation() throws -> any CancellationHandle { CeremonyCancellation() }
    func execute(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> JSONValue { requests.withLock { $0.append(request) }; return .object(["ok": .bool(true), "body": .object([:])]) }
    func executeSecret(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> JSONValue { throw BridgeError.invalidInput }
    func executeSecretResponse(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> SecretBytes { try reply(request) }
    func executeSecretRequestResponse(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> SecretBytes { try reply(request.request) }
    private func reply(_ request: CoreRequest) throws -> SecretBytes {
        requests.withLock { $0.append(request) }
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
