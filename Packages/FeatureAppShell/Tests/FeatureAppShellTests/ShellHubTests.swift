// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureAppShell

@Suite(.timeLimit(.minutes(1)))
struct ShellHubTests {
    @Test func moreHubKeepsTheDesignedRowsThenAccountsAndNotices() {
        #expect(MoreHub.items == [
            .route(.contacts), .route(.tasks), .route(.permissions), .route(.settings),
            .accounts, .route(.notices),
        ])
        for item in MoreHub.items {
            let english = FeatureAppShellStrings.text(item.titleKey, locale: Locale(identifier: "en"))
            let chinese = FeatureAppShellStrings.text(item.titleKey, locale: Locale(identifier: "zh-CN"))
            let preview = FeatureAppShellStrings.text(item.previewKey, locale: Locale(identifier: "en"))
            #expect(english != item.titleKey)
            #expect(chinese != item.titleKey)
            #expect(preview != item.previewKey)
        }
        #expect(FeatureAppShellStrings.text("shell.notices.title", locale: Locale(identifier: "zh-CN")) == "开源声明")
        #expect(AppTab.agents.title(locale: Locale(identifier: "zh-CN")) == "Agents")
    }
}
