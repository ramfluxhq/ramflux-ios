// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import AppData
struct PreferencesRepositoryTests {
    @Test func namedThemePersistsPerDeviceAndReloadsWithoutChangingAccounts() async {
        let suite = "theme-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let first = NativePreferencesRepository(suite: suite)
        let mode = AppearanceMode(rawValue: "additional-palette")
        guard let mode else { Issue.record("Named palette refused"); return }
        #expect(await first.setAppearance(mode) == .success(mode))
        #expect(await NativePreferencesRepository(suite: suite).appearance() == mode)
    }
}
