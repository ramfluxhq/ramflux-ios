// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UIKit
import Push

/// Receives the APNs device token callbacks. The token is not kept or logged: only its length and the failure code.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        ApnsTokenSource.shared.received(deviceToken)
        PushLog.token.notice("push.token.ok len=\(deviceToken.count, privacy: .public)")
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        let code = (error as NSError).code
        ApnsTokenSource.shared.failed(code: code)
        PushLog.token.notice("push.token.failed code=\(code, privacy: .public)")
    }
}
