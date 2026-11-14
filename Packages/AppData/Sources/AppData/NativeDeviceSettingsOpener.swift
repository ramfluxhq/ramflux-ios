// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
/// Keep the originating active scene when launching the public Settings routes.
@MainActor final class NativeDeviceSettingsOpener {
    private let activeScene: @MainActor () -> UIWindowScene?
    private let openURL: @MainActor (UIWindowScene, URL) async -> Bool
    init(activeScene: @escaping @MainActor () -> UIWindowScene? = {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        return scenes.first { $0.windows.contains(where: \.isKeyWindow) } ?? scenes.first
    }, openURL: @escaping @MainActor (UIWindowScene, URL) async -> Bool = { scene, url in
        await scene.open(url, options: UIScene.OpenExternalURLOptions())
    }) {
        self.activeScene = activeScene; self.openURL = openURL
    }
    func open(_ destination: DeviceSettingsDestination) async -> DeviceSettingsOpenResult {
        guard let scene = activeScene() else { return .deferred }
        let address = destination == .notifications ? UIApplication.openNotificationSettingsURLString : UIApplication.openSettingsURLString
        guard let url = URL(string: address) else { return .failed }
        return await openURL(scene, url) ? .opened : .failed
    }
}
#endif
