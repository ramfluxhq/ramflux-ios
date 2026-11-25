// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Push
#if os(iOS)
import UIKit
import UserNotifications
#endif

/// The only reader of the iOS delivery signals: notification settings, Background App Refresh and Low Power Mode
/// (the same rule as the permissions repository). The delivery status and the last wake times come from the
/// App Group store the registrar and the wake processor write.
public struct NativeDeliverySignalsRepository: DeliveryRepository {
    private let store: DeliveryLocalStore?
    public init(store: DeliveryLocalStore? = DeliveryLocalStore()) { self.store = store }
    public func snapshot(account: String?) async -> DeliverySnapshot {
        var snapshot = DeliverySnapshot(status: account.flatMap { store?.status(account: $0) } ?? .pending)
        for wake in [WakeClass.message, .call, .clear, .test] { if let date = store?.lastWake(wake) { snapshot.lastWake[wake] = date } }
        #if os(iOS)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        func map(_ value: UNNotificationSetting) -> DeliverySetting { switch value { case .enabled: .on; case .disabled: .off; default: .notSupported } }
        var shown = DeliveryNotificationSettings()
        shown.allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        shown.lockScreen = map(settings.lockScreenSetting); shown.notificationCenter = map(settings.notificationCenterSetting)
        shown.banners = map(settings.alertSetting); shown.sounds = map(settings.soundSetting); shown.badges = map(settings.badgeSetting)
        shown.timeSensitive = map(settings.timeSensitiveSetting); shown.scheduledSummary = map(settings.scheduledDeliverySetting)
        shown.showPreviews = switch settings.showPreviewsSetting { case .always: "always"; case .whenAuthenticated: "whenUnlocked"; case .never: "never"; @unknown default: "always" }
        snapshot.settings = shown
        if !shown.allowed, snapshot.status != .notConfigured { snapshot.status = .notificationsOff }
        snapshot.backgroundRefresh = await MainActor.run {
            switch UIApplication.shared.backgroundRefreshStatus { case .available: .enabled; case .denied: .disabled; case .restricted: .restricted; @unknown default: .enabled }
        }
        snapshot.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        #endif
        return snapshot
    }
    public func scheduleSelfTest() async -> Bool {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        let content = GenericContent.make(.test)
        let request = UNNotificationRequest(identifier: "ramflux.selftest", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        do { try await center.add(request); return true } catch { return false }
        #else
        return false
        #endif
    }
}
