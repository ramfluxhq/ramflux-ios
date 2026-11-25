// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UserNotifications

/// Category ids and the single-slot rule of system notifications. A pushed message is one notification per
/// account and device (the node's collapse id); the local notification of the running app uses a fixed request
/// id per account, `ramflux.message.local.<n>`, and the extension removes it before a pushed one is shown.
public enum MessageNotificationSlot {
    public static let message = "RF_MESSAGE", call = "RF_CALL", test = "RF_TEST", notice = "RF_NOTICE"
    public static let localPrefix = "ramflux.message.local."
    public static func localIdentifier(slot: Int) -> String { localPrefix + String(slot) }
    /// Declares the categories (no actions, no previews, no sender text).
    public static func categories() -> Set<UNNotificationCategory> {
        Set([message, call, test, notice].map { UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [], options: []) })
    }
    /// Ids of delivered local message notifications, to be removed.
    public static func localIdentifiers(in delivered: [UNNotification]) -> [String] {
        delivered.map(\.request.identifier).filter { $0.hasPrefix(localPrefix) }
    }
}
