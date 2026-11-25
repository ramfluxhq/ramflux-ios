// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UserNotifications

/// Builds notification content from fixed catalog texts only: no sender, conversation, thread, attachment or
/// message text ever reaches it.
public enum GenericContent {
    public enum Kind: Sendable { case message, call, test, unlockNotice }
    public static func kind(for wakeClass: WakeClass) -> Kind {
        switch wakeClass { case .call: .call; case .test: .test; default: .message }
    }
    public static func make(_ kind: Kind, from original: UNNotificationContent? = nil, locale: Locale = .current) -> UNMutableNotificationContent {
        let content = (original?.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        content.title = ""; content.subtitle = ""
        switch kind {
        case .message: content.body = PushStrings.text("push.message.body", locale: locale); content.categoryIdentifier = MessageNotificationSlot.message
        case .call: content.body = PushStrings.text("push.call.body", locale: locale); content.categoryIdentifier = MessageNotificationSlot.call
        case .test: content.body = PushStrings.text("push.test.body", locale: locale); content.categoryIdentifier = MessageNotificationSlot.test
        case .unlockNotice: content.body = PushStrings.text("push.locked.body", locale: locale); content.categoryIdentifier = MessageNotificationSlot.notice
        }
        content.threadIdentifier = ""; content.attachments = []
        return content
    }
}
