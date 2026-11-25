// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
@preconcurrency import UserNotifications
import Push

/// Notification service extension. At this stage it passes the alert through with the fixed catalog body; later
/// tasks add the wake fetch and the show or suppress decision.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        PushLog.nse.notice("push.nse.received")
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        content.body = PushStrings.text("push.message.body")
        self.handler = contentHandler
        self.content = content
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        PushLog.nse.notice("push.nse.expired")
        if let content { handler?(content) }
    }
}
