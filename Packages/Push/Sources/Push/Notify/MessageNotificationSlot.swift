// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
@preconcurrency import UserNotifications

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
    /// Removes the delivered local message notifications (the pushed one replaces them).
    public static func removeDeliveredLocal() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            center.getDeliveredNotifications { continuation.resume(returning: localIdentifiers(in: $0)) }
        }
        if !identifiers.isEmpty { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    }
    /// Posts the generic "Missed call" notification when alerts are allowed. It names no caller.
    public static func postMissedCall() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional, settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled else { return }
        let content = GenericContent.make(.missedCall)
        try? await center.add(UNNotificationRequest(identifier: "ramflux.call.missed", content: content, trigger: nil))
    }
    /// Removes every delivered message notification (pushed and local): a clear wake says the messages were read
    /// elsewhere (a pushed one is recognised by its category, or by its `rf` class when the extension did not run). Returns how many were removed.
    @discardableResult public static func removeDeliveredMessages() async -> Int {
        let center = UNUserNotificationCenter.current()
        let identifiers = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            center.getDeliveredNotifications { delivered in
                continuation.resume(returning: delivered.filter { $0.request.content.categoryIdentifier == message || $0.request.identifier.hasPrefix(localPrefix) || WakePayload(userInfo: $0.request.content.userInfo).wakeClass == .message }.map(\.request.identifier))
            }
        }
        if !identifiers.isEmpty { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
        return identifiers.count
    }
}
