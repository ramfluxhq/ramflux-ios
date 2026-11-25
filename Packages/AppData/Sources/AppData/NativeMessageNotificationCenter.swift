// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
#if os(iOS)
import UserNotifications
#endif
import Push

/// The system notification centre for message notifications. It never requests authorisation (that is the
/// permission flow's job, `NativeDevicePermissionsRepository`); it posts only when alerts are allowed and sets
/// the badge only when badges are allowed. Content is the catalog's generic "New message" and nothing else.
public struct NativeMessageNotificationCenter: MessageNotificationCenter {
    /// The `userInfo` key of the in-memory route token.
    public static let tokenKey = "ramflux.route"
    public init() {}
    public func post(token: String) async {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus), settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = AppDataStrings.text("notification.message.title")
        content.categoryIdentifier = MessageNotificationSlot.message
        content.sound = settings.soundSetting == .enabled ? .default : nil
        content.userInfo = [Self.tokenKey: token]
        try? await center.add(UNNotificationRequest(identifier: token, content: content, trigger: nil))
        #endif
    }
    public func setBadge(_ count: Int) async {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().badgeSetting == .enabled else { return }
        try? await center.setBadgeCount(max(0, count))
        #endif
    }
    public func removeDelivered() async {
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        #endif
    }
}
