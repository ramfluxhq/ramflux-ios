// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization

/// A moment in an account's life that account-scoped stores (media caches, drafts, decoded images)
/// must react to before the SDK closes the account.
public enum AccountLifecycleEvent: Equatable, Sendable {
    /// The account is about to be locked (`account.lock`): drop decoded plaintext held in memory.
    case willLock(account: String)
    /// The account is about to leave this device (sign-out or removal): purge everything it stored.
    case willRemove(account: String)
    /// The account is about to sign out or be removed from this device: clear what the node holds for it (push route).
    case willLeave(account: String)
}

/// Registry of account lifecycle handlers. Handlers run in registration order and are awaited before
/// the triggering SDK call is sent, so nothing they must purge outlives the open account.
public final class AccountLifecycleHooks: Sendable {
    public typealias Handler = @Sendable (AccountLifecycleEvent) async -> Void
    private let handlers = Mutex<[(UUID, Handler)]>([])
    public init() {}
    /// Registers a handler; keep the token and pass it to `unregister` when the store goes away.
    @discardableResult public func register(_ handler: @escaping Handler) -> UUID {
        let id = UUID(); handlers.withLock { $0.append((id, handler)) }; return id
    }
    public func unregister(_ token: UUID) { handlers.withLock { $0.removeAll { $0.0 == token } } }
    public func notify(_ event: AccountLifecycleEvent) async {
        for (_, handler) in handlers.withLock({ $0 }) { await handler(event) }
    }
}
