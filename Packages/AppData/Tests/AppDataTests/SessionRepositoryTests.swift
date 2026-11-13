// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import RamfluxCore
@testable import AppData

private struct NoCancellation: CancellationHandle { func cancel() {} }
private final class SessionTransport: CoreTransport {
    private let recorded = Mutex<[CoreRequest]>([])
    var calls: [CoreRequest] { recorded.withLock { $0 } }
    func newCancellation() throws -> any CancellationHandle { NoCancellation() }
    func execute(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> JSONValue { throw BridgeError.invalidInput }
    func executeSecret(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> JSONValue { throw BridgeError.invalidInput }
    func executeSecretResponse(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> SecretBytes {
        recorded.withLock { $0.append(request) }
        return try seal(.object(["accounts": .array([.string("account")]), "active_account_id": .null]))
    }
    func executeSecretRequestResponse(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> SecretBytes {
        recorded.withLock { $0.append(request.request) }
        return try seal(.object(["active_account_id": .string("account")]))
    }
    func start() throws {}
    func suspend() throws -> JSONValue { .object(["data_root_lock_released": .bool(true)]) }
    func resume() throws {}
    func close() throws {}
    func resetEvents() throws {}
    func subscribe(_ filter: SubscriptionFilter) throws -> any EventQueue { throw BridgeError.invalidInput }
}
private func seal(_ body: JSONValue) throws -> SecretBytes {
    let bytes = try JSONEncoder().encode(JSONValue.object(["code": .number(0), "response": .object(["ok": .bool(true), "body": body])]))
    return try bytes.withUnsafeBytes { try SecretBytes(copying: $0) }
}
@Suite(.timeLimit(.minutes(1))) struct SessionRepositoryTests {
    @Test func realProxyMapsAccountsAndPreservesSelectionContext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SessionTransport()
        let repository = NativeSessionRepository(client: RamfluxClient(transport: transport), dataRoot: root)
        let stream = await repository.snapshots()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.phase == .stopped)
        guard case .success(let ready) = await repository.activate() else { Issue.record("Activation failed"); return }
        #expect(ready.accounts.map(\.id) == ["account"])
        #expect(ready.activeAccountID == nil)
        #expect(await iterator.next()?.phase == .ready)
        #expect(transport.calls.first?.method == "account.list")
        #expect(transport.calls.first?.operationID == nil)
        guard case .failure(.locked) = await repository.selectAccount("unknown") else { Issue.record("Unknown account must refuse"); return }
        #expect(transport.calls.count == 1)
        guard case .success(let selected) = await repository.selectAccount("account") else { Issue.record("Selection failed"); return }
        #expect(selected.activeAccountID == "account")
        #expect(transport.calls.last?.accountID == "account")
        #expect(transport.calls.last?.operationID != nil)
        guard case .success = await repository.suspend() else { Issue.record("Suspend failed"); return }
    }
    @Test func malformedAccountFramesFailClosedAndSealedResponseIsSingleUse() throws {
        let valid = try seal(.object(["accounts": .array([.string("account")])]))
        #expect(try NativeSessionRepository.decodeAccounts(valid).accounts.count == 1)
        #expect(throws: BridgeError.secretConsumed) { try NativeSessionRepository.decodeAccounts(valid) }
        for body: JSONValue in [
            .object([:]), .object(["accounts": .array([.string("a"), .string("a")])]),
            .object(["accounts": .array([.string("a")]), "active_account_id": .string("other")]),
        ] {
            let invalid = try seal(body)
            #expect(throws: AppFailure.invalidData) { try NativeSessionRepository.decodeAccounts(invalid) }
        }
    }
    @Test func sourceFactoryReturnsTypedUnavailableWithoutAccounts() async {
        #if !RF_NATIVE_SDK
        let result = await AppDataFactory.sessionRepository().activate()
        guard case .success(let snapshot) = result else { Issue.record("Expected unavailable snapshot"); return }
        #expect(snapshot.phase == .unavailable(.nativeCoreMissing))
        #expect(snapshot.accounts.isEmpty)
        #endif
    }
}
