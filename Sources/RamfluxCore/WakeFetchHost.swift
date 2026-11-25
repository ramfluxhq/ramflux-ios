// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CRamflux

/// What one wake fetch returned. `fetched` means transport receipt only: the core's S1A host neither decrypts nor
/// applies nor acknowledges the page.
public enum CoreWakeFetchOutcome: Sendable, Equatable {
    case fetched(count: Int), busy, locked, deadline
}

/// Swift side of `ramflux_v2_wake_fetch`: one account's inbox fetch without opening the full client, safe to call
/// from a notification extension. It never constructs a `NativeCore`. The call runs on its own thread (the core
/// blocks for up to 20 s) and takes the same shared-root custody provider as the app.
public enum WakeFetchHost {
    public static let maxBudgetMilliseconds: UInt64 = 20_000
    public static func fetch(dataRoot: URL, accountID: String, deadlineUnixMilliseconds: UInt64, leaseWaitMilliseconds: Int = 50,
                             custody: HostCustodyProvider = HostCustodyProvider()) async throws -> CoreWakeFetchOutcome {
        guard dataRoot.isFileURL, !accountID.isEmpty, (0...5_000).contains(leaseWaitMilliseconds) else { throw BridgeError.invalidInput }
        let configuration = try JSONValue.object([
            "data_root": .string(dataRoot.path), "account_id": .string(accountID),
            "deadline_ms": .string(String(deadlineUnixMilliseconds)), "lease_wait_ms": .number(Double(leaseWaitMilliseconds)),
        ]).encoded()
        return try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result { try run(configuration: configuration, custody: custody) })
            }
        }
    }
    private static func run(configuration: Data, custody: HostCustodyProvider) throws -> CoreWakeFetchOutcome {
        var table = custody.table()
        var pointer: UnsafeMutablePointer<RamfluxBuffer>?
        let code = configuration.withUnsafeBytes { bytes in
            ramflux_v2_wake_fetch(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &table, &pointer)
        }
        guard code == 0 else {
            if let pointer { rf_buffer_wipe_free(pointer) }
            throw CoreFailure(code: code, effect: .none)
        }
        let body = try JSONValue.decode(NativeBuffers.take(pointer))
        switch body["outcome"]?.string {
        case "busy": return .busy
        case "locked": return .locked
        case "deadline": return .deadline
        case "fetched":
            guard case .array(let items)? = body["items"] else { throw BridgeError.invalidResponse }
            return .fetched(count: items.count)
        default: throw BridgeError.invalidResponse
        }
    }
}
