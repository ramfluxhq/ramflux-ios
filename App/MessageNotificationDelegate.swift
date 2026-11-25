// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UserNotifications
import AppData

/// Receives taps on message notifications. Notifications are not shown while the app is active (the inbox is
/// on screen); a tap hands the in-memory route token to the composition, which opens the conversation through
/// the shell's route policy.
final class MessageNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let open: @MainActor @Sendable (String) -> Void
    init(open: @escaping @MainActor @Sendable (String) -> Void) { self.open = open }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Debug builds only: an alert push to the foreground app carrying `rf_debug` runs the wake path in-process.
        #if RAMFLUX_DEBUG_WAKE
        let info = notification.request.content.userInfo
        if info["rf_debug"] != nil { _ = await AppDelegate.remoteWake?(info) }
        #endif
        return []
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let token = response.notification.request.content.userInfo[NativeMessageNotificationCenter.tokenKey] as? String else { return }
        await open(token)
    }
}
