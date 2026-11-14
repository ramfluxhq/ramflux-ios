// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import AppData
@MainActor struct DevicePermissionsTests {
    @Test func notificationOfferIsConsumedExplicitlyAndScopedPerAccount() throws {
        let name = "permissions-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        // The legacy device-wide flag cannot identify which account saw an offer.
        defaults.set(true, forKey: "device.notifications.explanation.v1")
        let first = NativeDevicePermissionsRepository(defaults: defaults)
        #expect(!first.notificationOfferConsumed(accountID: "first"))
        let interrupted = NativeDevicePermissionsRepository(defaults: defaults)
        #expect(!interrupted.notificationOfferConsumed(accountID: "first"))
        first.consumeNotificationOffer(accountID: "first")
        let replacement = NativeDevicePermissionsRepository(defaults: defaults)
        #expect(replacement.notificationOfferConsumed(accountID: "first"))
        #expect(!replacement.notificationOfferConsumed(accountID: "second"))
        replacement.consumeNotificationOffer(accountID: "second")
        #expect(first.notificationOfferConsumed(accountID: "second"))
    }
}
