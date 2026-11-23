// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Native session and its projection mapper. Never passes SDK frames into feature modules.
public actor NativeSessionRepository: SessionRepository {
    private let client: RamfluxClient
    private let lifecycle: PhoneLifecycle
    private let proxy: SDKProxy
    private var observer: AsyncStream<SessionSnapshot>.Continuation?
    private var current = SessionSnapshot(phase: .stopped)
    private var revision: UInt64 = 0
    public init(client: RamfluxClient, dataRoot: URL) {
        self.client = client; proxy = SDKProxy(client: client); lifecycle = PhoneLifecycle(client: client, dataRoot: dataRoot)
    }
    public func snapshots() -> AsyncStream<SessionSnapshot> {
        observer?.finish()
        let pair = AsyncStream<SessionSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observer = pair.continuation; observer?.yield(current)
        return pair.stream
    }
    private func publish(_ value: SessionSnapshot) { current = value; observer?.yield(value) }
    public func activate() async -> RepositoryResult<SessionSnapshot> {
        revision &+= 1; let epoch = revision
        publish(SessionSnapshot(phase: .opening))
        do {
            try await lifecycle.foreground()
            let sealed = try await proxy.accountList(context: context())
            let snapshot = try Self.decodeAccounts(sealed)
            guard epoch == revision, !Task.isCancelled else { return .failure(.busy) }
            publish(snapshot); return .success(snapshot)
        } catch {
            let failure = AppFailure.map(error)
            if epoch == revision { publish(SessionSnapshot(phase: .failed(failure))) }
            return .failure(failure)
        }
    }
    public func suspend() async -> RepositoryResult<Void> {
        revision &+= 1; let epoch = revision
        publish(SessionSnapshot(phase: .suspended))
        do { try await lifecycle.background(); return .success(()) }
        catch { let failure = AppFailure.map(error); if epoch == revision { publish(SessionSnapshot(phase: .failed(failure))) }; return .failure(failure) }
    }
    public func selectAccount(_ id: String) async -> RepositoryResult<SessionSnapshot> {
        guard current.phase == .ready, current.accounts.contains(where: { $0.id == id && !$0.isLocked }) else { return .failure(.locked) }
        let epoch = revision
        do {
            let result = try await proxy.accountSwitch(context: context(account: id, operation: .fresh()))
            do { try Self.validateMutation(result) } catch { return .failure(.outcomeUnknown) }
            guard epoch == revision, !Task.isCancelled else { return .failure(.outcomeUnknown) }
            let snapshot = SessionSnapshot(phase: .ready, accounts: current.accounts, activeAccountID: id)
            publish(snapshot); return .success(snapshot)
        } catch { return .failure(AppFailure.map(error)) }
    }
    private func context(account: String? = nil, operation: OperationID? = nil) -> RequestContext {
        RequestContext(accountID: account, operationID: operation, deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 10_000)
    }
    static func decodeAccounts(_ sealed: SecretBytes) throws -> SessionSnapshot {
        try sealed.consume { bytes in
            let completion = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
            guard completion["code"] == .number(0), completion["response"]?["ok"] == .bool(true),
                  let body = completion["response"]?["body"], case .array(let values) = body["accounts"], values.count <= 4096 else { throw AppFailure.invalidData }
            // Every account held on this phone, open or locked, with its display name (`account.list` rows
            // `{id, display_name, locked}`); the active account is always an open one.
            let accounts = try values.map { value in
                guard let id = value["id"]?.string, !id.isEmpty, id.utf8.count <= 256, let locked = value["locked"]?.bool else { throw AppFailure.invalidData }
                let name = value["display_name"]?.string.flatMap { $0.isEmpty || $0.utf8.count > 1024 ? nil : $0 } ?? id
                return AccountRecord(id: id, displayName: name, isLocked: locked)
            }
            guard Set(accounts.map(\.id)).count == accounts.count else { throw AppFailure.invalidData }
            let active = body["active_account_id"]?.string
            guard active == nil || accounts.contains(where: { $0.id == active && !$0.isLocked }) else { throw AppFailure.invalidData }
            return SessionSnapshot(phase: .ready, accounts: accounts, activeAccountID: active)
        }
    }
    private static func validateMutation(_ sealed: SecretBytes) throws {
        try sealed.consume { bytes in
            let completion = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
            guard completion["code"] == .number(0), completion["response"]?["ok"] == .bool(true) else { throw AppFailure.outcomeUnknown }
        }
    }
    deinit { observer?.finish() }
}
