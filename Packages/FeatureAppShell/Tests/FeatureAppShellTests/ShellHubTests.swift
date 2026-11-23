// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureAppShell

@Suite(.timeLimit(.minutes(1)))
struct ShellHubTests {
    @Test func moreHubKeepsTheDesignedRowsThenCallsAccountsAndNotices() {
        #expect(MoreHub.items() == [
            .route(.contacts), .route(.tasks), .route(.permissions), .route(.settings),
            .navigation, .route(.calls(nil)), .accounts, .route(.notices),
        ])
        for item in MoreHub.items() {
            let english = FeatureAppShellStrings.text(item.titleKey, locale: Locale(identifier: "en"))
            let chinese = FeatureAppShellStrings.text(item.titleKey, locale: Locale(identifier: "zh-CN"))
            let preview = FeatureAppShellStrings.text(item.previewKey, locale: Locale(identifier: "en"))
            #expect(english != item.titleKey)
            #expect(chinese != item.titleKey)
            #expect(preview != item.previewKey)
        }
        #expect(FeatureAppShellStrings.text("shell.notices.title", locale: Locale(identifier: "zh-CN")) == "开源声明")
        #expect(FeatureAppShellStrings.text("shell.nav.title", locale: Locale(identifier: "en")) == "Edit mobile navigation")
        #expect(FeatureAppShellStrings.text("shell.nav.title", locale: Locale(identifier: "zh-CN")) == "编辑移动导航")
        #expect(FeatureAppShellStrings.text("shell.more.navigation", locale: Locale(identifier: "zh-CN")) == "编辑导航")
        #expect(AppTab.agents.title(locale: Locale(identifier: "zh-CN")) == "Agents")
    }

    @Test func shortcutsMatchTheAndroidEditorRules() {
        #expect(ShellShortcuts.hide("", id: "messages") == "")
        #expect(ShellShortcuts.hide("", id: "contacts") == "contacts")
        #expect(ShellShortcuts.hide("tasks", id: "contacts") == "contacts-tasks")
        #expect(ShellShortcuts.reveal("contacts-tasks") == "tasks")
        #expect(ShellShortcuts.reveal("") == "")
        let hidden = ShellShortcuts.hide("", id: "contacts")
        let moved = ShellShortcuts.move(ShellShortcuts.defaultOrder, hidden: hidden, index: 3, delta: -1)
        #expect(moved == "messages-groups-tasks-contacts-agents")
        #expect(ShellShortcuts.moreIds(order: moved, hidden: hidden) == ["tasks"])
        #expect(ShellShortcuts.move(ShellShortcuts.defaultOrder, hidden: "", index: 0, delta: -1) == ShellShortcuts.defaultOrder)
        #expect(ShellShortcuts.move(ShellShortcuts.defaultOrder, hidden: "", index: 4, delta: 1) == ShellShortcuts.defaultOrder)
        #expect(MoreHub.items(order: moved, hidden: hidden).first == .route(.tasks))
    }
}
