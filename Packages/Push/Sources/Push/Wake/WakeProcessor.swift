// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
@preconcurrency import UserNotifications

/// The whole wake path for one notification: parse, dispatch, remove the local slot, build the content. The
/// notification service extension and the debug injector both call `process`; the extension only hosts it.
public struct WakeProcessor: Sendable {
    public struct Output: @unchecked Sendable {
        public let result: WakeResult
        /// The content to deliver for a generic result, nil when nothing is to be shown.
        public let content: UNMutableNotificationContent?
    }
    private let dispatcher: WakeDispatcher
    public static let fetchBudget: Duration = .seconds(18)
    public init(dispatcher: WakeDispatcher) { self.dispatcher = dispatcher }

    public func process(payload: WakePayload, original: UNNotificationContent?, source: WakeSignal.Source,
                        overrideClass: WakeClass? = nil) async -> Output {
        let signal = WakeSignal(wakeClass: overrideClass ?? payload.wakeClass, routeTag: payload.routeTag, wakeID: payload.wakeID, source: source)
        let result = await dispatcher.handle(signal, deadline: .now + Self.fetchBudget)
        switch result {
        case .showGeneric(let kind):
            if kind == .message { await MessageNotificationSlot.removeDeliveredLocal() }
            return Output(result: result, content: GenericContent.make(kind, from: original))
        case .showUnlockNotice:
            return Output(result: result, content: GenericContent.make(.unlockNotice, from: original))
        case .clearMessages:
            let removed = await MessageNotificationSlot.removeDeliveredMessages()
            PushLog.wake.notice("push.clear.removed count=\(removed, privacy: .public)")
            return Output(result: result, content: nil)
        case .suppress, .ringCall, .ignore:
            return Output(result: result, content: nil)
        }
    }
}
