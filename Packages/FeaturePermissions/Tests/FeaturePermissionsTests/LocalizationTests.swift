// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import FeaturePermissions
struct LocalizationTests {
    @Test func englishChineseAndExpandedCopyResolveFromCatalog() {
        let en = FeaturePermissionsStrings.text("notifications.title", locale: Locale(identifier: "en"))
        let zh = FeaturePermissionsStrings.text("notifications.title", locale: Locale(identifier: "zh-CN"))
        let expanded = FeaturePermissionsStrings.text("notifications.title", locale: Locale(identifier: "en-XA"))
        let deniedEN = FeaturePermissionsStrings.text("denied", locale: Locale(identifier: "en"))
        let deniedZH = FeaturePermissionsStrings.text("denied", locale: Locale(identifier: "zh-CN"))
        #expect(deniedEN.contains("Settings › Apps › Ramflux"))
        #expect(deniedZH.contains("设置 › App › Ramflux"))
        #expect(en == "Turn on notifications?"); #expect(zh == "开启通知？"); #expect(expanded.count > en.count)
    }
}
