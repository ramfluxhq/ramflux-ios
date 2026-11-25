// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation

/// Posts and clears local message notifications. Content is generic: no message text, no sender and no
/// conversation id leave the app; a notification carries only a random token the running app maps back.
public protocol MessageNotificationCenter: Sendable {
    /// Posts one "New message" notification identified by `token` (only when notifications are authorised).
    func post(token: String) async
    /// Sets the app icon badge (only when badges are authorised).
    func setBadge(_ count: Int) async
    func removeDelivered() async
}

/// What one directory read asks for: conversations whose unread count rose while the app was not active,
/// and the badge.
public struct MessageNotificationPlan: Equatable, Sendable {
    public let notify: [String]
    public let badge: Int
    public init(notify: [String], badge: Int) { self.notify = notify; self.badge = badge }
}

/// Local notifications for messages that arrive while the app is not active and the process and core are
/// alive, driven by the shared event source. On every invalidation it reads the first directory page and
/// compares unread counts with the previous read; it keeps one notification per account. Limitations at this SDK pin: the directory is ordered by
/// conversation id, not activity, and has no account-wide unread total, so detection and the badge cover the
/// first `window` conversations only; the core is shut down when the app enters the background (to release
/// the database), so nothing is observed there. Background delivery needs push routes and a decrypting
/// extension (docs/permissions.md).
@MainActor public final class MessageNotifier {
    private let conversations: any ConversationsRepository
    private let center: any MessageNotificationCenter
    private let window: Int
    private let slot: @Sendable (String) -> String
    private var account: String?
    private var active = true
    private var previous: [String: UInt]?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    /// Slot identifiers of posted notifications and their accounts; kept only in memory, so a tap after the
    /// process ended opens the app only.
    private var routes: [String: String] = [:]
    public static let defaultWindow = 100
    public init(conversations: any ConversationsRepository, center: any MessageNotificationCenter, window: Int = MessageNotifier.defaultWindow,
                slot: @escaping @Sendable (String) -> String = { AccountSlots.localIdentifier(account: $0) }) {
        self.conversations = conversations; self.center = center; self.window = window; self.slot = slot
    }
    /// Follows `account` (nil stops). Following the same account while it runs does nothing.
    public func follow(account: String?) {
        guard account != self.account || (account != nil && task == nil) else { return }
        generation &+= 1; task?.cancel(); task = nil; previous = nil
        if account != self.account { routes = [:] }
        self.account = account
        guard let account else { return }
        let current = generation
        task = Task { [weak self, conversations] in
            let observation = await conversations.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self, self.generation == current else { break }
                guard case .invalidated = update else { break }
                await self.read(account: account, generation: current)
            }
            await observation.stop()
            if let self, self.generation == current { self.task = nil }
        }
    }
    /// The app is in the foreground and active: no notifications, and delivered ones are cleared. Routes stay,
    /// because the tap that activated the app is reported after activation.
    public func setActive(_ value: Bool) {
        active = value
        if value { Task { [center] in await center.removeDelivered() } }
    }
    /// The account of a tapped notification, if this process posted it. A tap opens that account's chat list.
    public func account(for token: String) -> String? { routes[token] }

    private func read(account: String, generation current: UInt64) async {
        guard case .success(let page) = await conversations.page(account: account, cursor: nil, limit: window), self.generation == current else { return }
        let plan = Self.plan(previous: previous, rows: page.rows, active: active)
        previous = Dictionary(page.rows.map { ($0.id, $0.unreadCount ?? 0) }, uniquingKeysWith: { first, _ in first })
        await center.setBadge(plan.badge)
        // One notification per account: a later one replaces the earlier one in the same slot.
        if !plan.notify.isEmpty {
            let token = slot(account)
            routes[token] = account
            await center.post(token: token)
        }
    }
    /// The first read only records a baseline; muted conversations neither notify nor count in the badge.
    public nonisolated static func plan(previous: [String: UInt]?, rows: [ConversationRecord], active: Bool) -> MessageNotificationPlan {
        let audible = rows.filter { !$0.muted }
        let badge = audible.reduce(0) { $0 + Int($1.unreadCount ?? 0) }
        guard let previous, !active else { return MessageNotificationPlan(notify: [], badge: badge) }
        return MessageNotificationPlan(notify: audible.filter { ($0.unreadCount ?? 0) > (previous[$0.id] ?? 0) }.map(\.id), badge: badge)
    }
}
