// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization

/// The APNs device token of this process, in memory only. The app delegate reports it; the route registrar reads it.
public final class ApnsTokenSource: Sendable {
    public static let shared = ApnsTokenSource()
    private struct State { var token: String?; var failureCode: Int?; var handlers: [(UUID, @Sendable () -> Void)] = [] }
    private let state = Mutex(State())
    public init() {}
    public var token: String? { state.withLock { $0.token } }
    /// The error code of the last failed registration with Apple, if no token followed it.
    public var failureCode: Int? { state.withLock { $0.failureCode } }
    public func received(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let handlers = state.withLock { state -> [(UUID, @Sendable () -> Void)] in
            guard state.token != hex else { return [] }
            state.token = hex; state.failureCode = nil; return state.handlers
        }
        handlers.forEach { $0.1() }
    }
    public func failed(code: Int) { state.withLock { $0.token = nil; $0.failureCode = code } }
    /// Calls `handler` whenever a different token arrives.
    @discardableResult public func onChange(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID(); state.withLock { $0.handlers.append((id, handler)) }; return id
    }
}
