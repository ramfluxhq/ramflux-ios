// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
@preconcurrency import UserNotifications
import Push

/// Notification service extension. It shows the fixed generic text of the wake's class (never message content);
/// for a message it first removes the running app's local notification, so one account has one notification.
/// Later tasks add the wake fetch and the show or suppress decision.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        PushLog.nse.notice("push.nse.received")
        let payload = WakePayload(userInfo: request.content.userInfo)
        let kind = GenericContent.kind(for: payload.wakeClass)
        let content = GenericContent.make(kind, from: request.content)
        self.handler = contentHandler
        self.content = content
        guard kind == .message else { contentHandler(content); return }
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers: MessageNotificationSlot.localIdentifiers(in: delivered))
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        PushLog.nse.notice("push.nse.expired")
        if let content { handler?(content) }
    }
}
