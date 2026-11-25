// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
@preconcurrency import UserNotifications
import Push

/// Notification service extension: a thin host. Everything a wake does is `WakeProcessor`, which the app's debug
/// injector runs in-process as well; only the hosting below (extension lifecycle, the system's delivery of the
/// content and its time limit) differs between the two paths.
final class NotificationService: UNNotificationServiceExtension {
    /// Delivers the content once: either the processor's answer or, at the time limit, the best attempt.
    private final class Delivery: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: ((UNNotificationContent) -> Void)?
        let best: UNNotificationContent
        var task: Task<Void, Never>?
        init(handler: @escaping (UNNotificationContent) -> Void, best: UNNotificationContent) { self.handler = handler; self.best = best }
        func finish(_ content: UNNotificationContent?) {
            lock.lock(); let current = handler; handler = nil; lock.unlock()
            current?(content ?? best)
        }
    }
    private var delivery: Delivery?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        PushLog.nse.notice("push.nse.received")
        // Until the processor answers, the best attempt is the generic message text.
        let delivery = Delivery(handler: contentHandler, best: GenericContent.make(.message, from: request.content))
        self.delivery = delivery
        let processor = WakeHost.processor()
        let payload = WakePayload(userInfo: request.content.userInfo)
        let box = UncheckedRequest(request.content)
        delivery.task = Task {
            let output = await processor.process(payload: payload, original: box.content, source: .notificationService)
            delivery.finish(output.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        PushLog.nse.notice("push.nse.expired")
        delivery?.task?.cancel()
        delivery?.finish(nil)
    }
}

private struct UncheckedRequest: @unchecked Sendable {
    let content: UNNotificationContent
    init(_ content: UNNotificationContent) { self.content = content }
}
