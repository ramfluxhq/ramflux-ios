// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeatureMlsGroups
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromPackageCatalog() {
        let english = FeatureMlsGroupsStrings.text("group.list.title", locale: Locale(identifier: "en"))
        let chinese = FeatureMlsGroupsStrings.text("group.list.title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeatureMlsGroupsStrings.text("group.list.title", locale: Locale(identifier: "en-XA"))
        #expect(english != "group.list.title"); #expect(chinese != english); #expect(expanded.count > english.count)
    }
}

struct HostNoticeFlagTests {
    @Test @MainActor func removingAnAccountPurgesItsHostNoticeFlagsOnly() throws {
        let defaults = try #require(UserDefaults(suiteName: "mls-notice-test-" + UUID().uuidString))
        defaults.set(true, forKey: MlsGroupsCoordinator.noticeKey(account: "a1", group: "g1"))
        defaults.set(true, forKey: MlsGroupsCoordinator.noticeKey(account: "a1", group: "g2"))
        defaults.set(true, forKey: MlsGroupsCoordinator.noticeKey(account: "a2", group: "g1"))
        MlsGroupsCoordinator.purgeNoticeFlags(account: "a1", defaults: defaults)
        #expect(!defaults.bool(forKey: MlsGroupsCoordinator.noticeKey(account: "a1", group: "g1")))
        #expect(!defaults.bool(forKey: MlsGroupsCoordinator.noticeKey(account: "a1", group: "g2")))
        #expect(defaults.bool(forKey: MlsGroupsCoordinator.noticeKey(account: "a2", group: "g1")))
    }
}
