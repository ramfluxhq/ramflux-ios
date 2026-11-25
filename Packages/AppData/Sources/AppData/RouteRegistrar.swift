// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Push

/// Keeps the push route of the unlocked account registered. Debug builds send the raw APNs token to the node the
/// developer runs (design D4); Release builds wait for the central service, which seals the token. Log lines are
/// codes only.
public actor RouteRegistrar {
    private let repository: any PushRouteRepository
    private let registry: RouteRegistry?
    private let store: DeliveryLocalStore?
    private let tokens: ApnsTokenSource
    private var attempted: Set<String> = []
    public init(repository: any PushRouteRepository, registry: RouteRegistry?, store: DeliveryLocalStore?, tokens: ApnsTokenSource = .shared) {
        self.repository = repository; self.registry = registry; self.store = store; self.tokens = tokens
    }
    public func status(account: String) -> DeliveryStatus { store?.status(account: account) ?? .pending }
    /// Registers `account` (unlocked and connected) when a token is known; otherwise records why not.
    @discardableResult public func register(account: String) async -> DeliveryStatus {
        attempted.insert(account)
        #if DEBUG
        guard let token = tokens.token else {
            let status: DeliveryStatus = tokens.failureCode.map { $0 == 3000 ? .notConfigured : .appleFailed } ?? .pending
            store?.setStatus(status, account: account); return status
        }
        guard let tag = registry?.ensureTag(for: account) else { store?.setStatus(.retrying, account: account); return .retrying }
        _ = store?.tokenChanged(token, account: account)
        let answer = await repository.register(account: account, token: token, routeTag: tag, sandbox: true)
        let status: DeliveryStatus
        switch answer {
        case .registered: status = .ready; PushLog.route.notice("push.route.sent")
        case .refused(let code):
            // Until the ABI carries the typed code (CR4) the generic refusal stands for "the node has no APNs credential".
            status = code.contains("provider_unavailable") || code == "invalid_argument" ? .serverNoPush : .retrying
            PushLog.route.notice("push.route.refused.\(code.prefix(40), privacy: .public)")
        default: status = .retrying; PushLog.route.notice("push.route.failed")
        }
        store?.setStatus(status, account: account)
        return status
        #else
        store?.setStatus(.waitingForCentre, account: account); return .waitingForCentre
        #endif
    }
    /// A different token arrived: registers the accounts seen since launch (the others register on their next unlock).
    public func tokenChanged() async { for account in attempted { await register(account: account) } }
    /// Clears the node's route and forgets the tag before the account's stores are erased. Best effort: gives up
    /// after five seconds, because the tag is dropped either way and the node then sees an unknown tag.
    public func deregister(account: String) async {
        attempted.remove(account)
        let repository = self.repository
        await withTaskGroup(of: Void.self) { group in
            group.addTask { if await repository.deregister(account: account) != .deregistered { PushLog.route.notice("push.route.deregister.failed") } }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next(); group.cancelAll()
        }
        registry?.remove(account: account); store?.forget(account: account)
    }
}
