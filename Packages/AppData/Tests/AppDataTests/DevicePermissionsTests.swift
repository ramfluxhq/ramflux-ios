// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import AppData
@MainActor struct DevicePermissionsTests {
    @Test func notificationOfferPersistsLocallyAcrossRepositoryInstances() throws {
        let name = "permissions-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = NativeDevicePermissionsRepository(defaults: defaults)
        #expect(first.claimNotificationOffer()); #expect(!first.claimNotificationOffer())
        let replacement = NativeDevicePermissionsRepository(defaults: defaults)
        #expect(!replacement.claimNotificationOffer())
    }
}
