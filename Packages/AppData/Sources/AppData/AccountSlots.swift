// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Push

/// A stable small number per account on this phone, so each account has one local notification slot
/// (`ramflux.message.local.<n>`). Numbers are handed out in the order accounts are first seen.
public enum AccountSlots {
    private static let key = "push.accountSlots.v1"
    private static let lock = NSLock()
    public static func localIdentifier(account: String, defaults: UserDefaults = .standard) -> String {
        MessageNotificationSlot.localIdentifier(slot: index(for: account, defaults: defaults))
    }
    static func index(for account: String, defaults: UserDefaults) -> Int {
        lock.lock(); defer { lock.unlock() }
        var slots = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        if let known = slots[account] { return known }
        let next = (slots.values.max() ?? -1) + 1
        slots[account] = next; defaults.set(slots, forKey: key)
        return next
    }
}
