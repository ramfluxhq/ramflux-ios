// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// The app lock of one account as the SDK reports it (`account.app_lock.state`). Off by default.
public struct AppLockRecord: Equatable, Sendable {
    /// `armed` (the deadline runs, access is still open) reads as unlocked. Any other state the SDK may name is
    /// `locked`: an unknown state fails closed, so the shell covers the records and asks for the code.
    public enum State: Equatable, Sendable { case unlocked, locked, unavailable }
    public let enabled: Bool
    public let timeoutMilliseconds: UInt64
    public let state: State
    public let remainingMilliseconds: UInt64?
    /// The wait in whole seconds before the next account-code check is allowed (`code_retry_after_secs`); nil when none applies.
    public let codeRetryAfterSeconds: UInt64?
    /// The account-code checks are used up; only the recovery phrase restores the account (`code_attempts_exhausted`).
    public let codeAttemptsExhausted: Bool
    public init(enabled: Bool, timeoutMilliseconds: UInt64, state: State, remainingMilliseconds: UInt64?,
                codeRetryAfterSeconds: UInt64? = nil, codeAttemptsExhausted: Bool = false) {
        self.enabled = enabled; self.timeoutMilliseconds = timeoutMilliseconds; self.state = state; self.remainingMilliseconds = remainingMilliseconds
        self.codeRetryAfterSeconds = codeRetryAfterSeconds; self.codeAttemptsExhausted = codeAttemptsExhausted
    }
    static func decode(_ body: JSONValue) throws -> AppLockRecord {
        guard let enabled = body["enabled"]?.bool, let name = body["state"]?.string,
              let timeout = ProxyGateway.integer(body["timeout_ms"]), timeout >= 0, timeout <= 86_400_000 else { throw AppFailure.invalidData }
        let state: State = switch name {
        case "unlocked", "armed": .unlocked
        case "unavailable": .unavailable
        default: .locked
        }
        let remaining = ProxyGateway.integer(body["remaining_ms"]).flatMap { $0 >= 0 ? UInt64($0) : nil }
        let retry = ProxyGateway.integer(body["code_retry_after_secs"]).flatMap { $0 > 0 ? UInt64($0) : nil }
        return AppLockRecord(enabled: enabled, timeoutMilliseconds: UInt64(timeout), state: state, remainingMilliseconds: remaining,
                             codeRetryAfterSeconds: retry, codeAttemptsExhausted: body["code_attempts_exhausted"]?.bool == true)
    }
}

/// The lifecycle the SDK arms or cancels the app-lock deadline with (`account.app_lock.lifecycle`).
enum AppLockPhase: String, Sendable { case background, foreground }

/// The timeouts the App lock page offers, in milliseconds (the SDK accepts 0 to 86_400_000).
public enum AppLockTimeout: UInt64, CaseIterable, Identifiable, Sendable {
    case immediately = 0, oneMinute = 60_000, fiveMinutes = 300_000, fifteenMinutes = 900_000, oneHour = 3_600_000
    public var id: UInt64 { rawValue }
}

/// Calls of the app-lock methods. Only AppData talks to the SDK for them; the operation proxies already exist.
struct AppLockService: Sendable {
    let gateway: ProxyGateway
    /// The client's event hub: the SDK refuses app-lock calls for another account on a connection whose subscription is
    /// attended for one, so each call runs with that subscription detached (see `NativeUpdateSource.unattended`).
    var stream: NativeUpdateSource?
    init(gateway: ProxyGateway, stream: NativeUpdateSource? = nil) { self.gateway = gateway; self.stream = stream }
    private func leased<T: Sendable>(_ account: String, _ call: @Sendable () async throws -> T) async throws -> T {
        guard let stream else { return try await call() }
        return try await stream.unattended(for: account, call)
    }
    func state(account: String) async throws -> AppLockRecord {
        try await leased(account) { try AppLockRecord.decode(try await gateway.call(.accountAppLockState, account: account)) }
    }
    func configure(account: String, enabled: Bool, timeoutMilliseconds: UInt64, credentials: @escaping CredentialAsk, operationID: String) async throws -> AppLockRecord {
        try await leased(account) {
            _ = try await gateway.callAttended(.accountAppLockConfigure, account: account,
                                               body: .object(["enabled": .bool(enabled), "timeout_ms": .number(Double(timeoutMilliseconds))]),
                                               operationID: operationID, credentials: credentials)
            return try await state(account: account)
        }
    }
    /// The reply is the lock as the core holds it after the call: the foreground may engage an expired lock at once.
    func lifecycle(account: String, _ phase: AppLockPhase) async throws -> AppLockRecord {
        try await leased(account) { try AppLockRecord.decode(try await gateway.call(.accountAppLockLifecycle, account: account, body: .object(["state": .string(phase.rawValue)]), operationID: UUID().uuidString)) }
    }
}
