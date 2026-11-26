// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// The app lock of one account as the SDK reports it (`account.app_lock.state`). Off by default.
public struct AppLockRecord: Equatable, Sendable {
    public enum State: String, Sendable { case unlocked, locked, unavailable }
    public let enabled: Bool
    public let timeoutMilliseconds: UInt64
    public let state: State
    public let remainingMilliseconds: UInt64?
    public init(enabled: Bool, timeoutMilliseconds: UInt64, state: State, remainingMilliseconds: UInt64?) {
        self.enabled = enabled; self.timeoutMilliseconds = timeoutMilliseconds; self.state = state; self.remainingMilliseconds = remainingMilliseconds
    }
    static func decode(_ body: JSONValue) throws -> AppLockRecord {
        guard let enabled = body["enabled"]?.bool, let state = body["state"]?.string.flatMap(State.init(rawValue:)),
              let timeout = ProxyGateway.integer(body["timeout_ms"]), timeout >= 0, timeout <= 86_400_000 else { throw AppFailure.invalidData }
        let remaining = ProxyGateway.integer(body["remaining_ms"]).flatMap { $0 >= 0 ? UInt64($0) : nil }
        return AppLockRecord(enabled: enabled, timeoutMilliseconds: UInt64(timeout), state: state, remainingMilliseconds: remaining)
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
    func state(account: String) async throws -> AppLockRecord {
        try AppLockRecord.decode(try await gateway.call(.accountAppLockState, account: account))
    }
    func configure(account: String, enabled: Bool, timeoutMilliseconds: UInt64, operationID: String) async throws -> AppLockRecord {
        _ = try await gateway.call(.accountAppLockConfigure, account: account,
                                   body: .object(["enabled": .bool(enabled), "timeout_ms": .number(Double(timeoutMilliseconds))]), operationID: operationID)
        return try await state(account: account)
    }
    func lifecycle(account: String, _ phase: AppLockPhase) async throws {
        _ = try await gateway.call(.accountAppLockLifecycle, account: account, body: .object(["state": .string(phase.rawValue)]), operationID: UUID().uuidString)
    }
}
