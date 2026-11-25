// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Push

/// One iOS setting as the delivery page shows it.
public enum DeliverySetting: Equatable, Sendable { case on, off, notSupported }

/// The notification settings of this iPhone for Ramflux (`UNNotificationSettings`), reduced to what the page shows.
public struct DeliveryNotificationSettings: Equatable, Sendable {
    public var allowed = false
    public var lockScreen = DeliverySetting.notSupported, notificationCenter = DeliverySetting.notSupported, banners = DeliverySetting.notSupported
    public var sounds = DeliverySetting.notSupported, badges = DeliverySetting.notSupported, timeSensitive = DeliverySetting.notSupported
    public var scheduledSummary = DeliverySetting.notSupported
    /// `always`, `whenUnlocked` or `never` (information only: notification texts are generic).
    public var showPreviews = "always"
    public init() {}
}

public enum BackgroundRefresh: Equatable, Sendable { case enabled, disabled, restricted }

/// Everything the page reads in one go.
public struct DeliverySnapshot: Equatable, Sendable {
    public var status: DeliveryStatus
    public var settings: DeliveryNotificationSettings
    public var backgroundRefresh: BackgroundRefresh
    public var lowPowerMode: Bool
    public var lastWake: [WakeClass: Date]
    public init(status: DeliveryStatus = .pending, settings: DeliveryNotificationSettings = DeliveryNotificationSettings(), backgroundRefresh: BackgroundRefresh = .enabled, lowPowerMode: Bool = false, lastWake: [WakeClass: Date] = [:]) {
        self.status = status; self.settings = settings; self.backgroundRefresh = backgroundRefresh; self.lowPowerMode = lowPowerMode; self.lastWake = lastWake
    }
}

public protocol DeliveryRepository: Sendable {
    func snapshot(account: String?) async -> DeliverySnapshot
    /// Posts a local test notification after five seconds (lock the phone to see it); false when notifications are off.
    func scheduleSelfTest() async -> Bool
}

public struct UnavailableDeliveryRepository: DeliveryRepository {
    public init() {}
    public func snapshot(account: String?) async -> DeliverySnapshot { DeliverySnapshot() }
    public func scheduleSelfTest() async -> Bool { false }
}
