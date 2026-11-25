// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Push

/// Handles a call wake that must ring (PushKit later, the debug injector now): reports a placeholder to the system
/// call UI at once, before any network or SDK work, and ends it as unanswered with a "Missed call" notification
/// when nothing connects within the timeout. The placeholder names no caller and cannot be answered while the
/// media engine refuses (docs/app-shell.md).
@MainActor public final class CallWakeHandler {
    public static let defaultTimeout: Duration = .seconds(45)
    private let bridge: CallSystemBridge
    private let timeout: Duration
    private let missed: @Sendable () async -> Void
    private var timer: Task<Void, Never>?
    public init(bridge: CallSystemBridge, timeout: Duration = CallWakeHandler.defaultTimeout, missed: @escaping @Sendable () async -> Void = { await MessageNotificationSlot.postMissedCall() }) {
        self.bridge = bridge; self.timeout = timeout; self.missed = missed
        bridge.onWakeDeclined = { [weak self] in PushLog.call.notice("push.call.declined"); self?.timer?.cancel(); self?.timer = nil }
    }
    /// Reports the placeholder. Returns whether the system UI accepted it.
    @discardableResult public func ring() async -> Bool {
        let call = CallSystemCall(uuid: UUID(), callID: "wake", handle: FeatureCallsStrings.text("calls.wake.caller"), video: false)
        // A refused report (Do Not Disturb, a block list, a system that cannot show the call) still ends as missed.
        let accepted = await bridge.reportWake(call)
        if accepted { PushLog.call.notice("push.call.reported") } else { PushLog.call.notice("push.call.refused") }
        timer?.cancel()
        timer = Task { [weak self, timeout, missed] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            self.bridge.endWake(reason: .unanswered)
            PushLog.call.notice("push.call.missed")
            await missed()
            self.timer = nil
        }
        return accepted
    }
}
