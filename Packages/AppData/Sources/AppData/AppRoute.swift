// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case messages, groups, agents, more
    public var id: Self { self }
    public var title: String { title(locale: .current) }
    public func title(locale: Locale) -> String { switch self { case .messages: AppDataStrings.text("common.tab.messages", locale: locale); case .groups: AppDataStrings.text("common.tab.groups", locale: locale); case .agents: AppDataStrings.text("common.tab.agents", locale: locale); case .more: AppDataStrings.text("common.tab.more", locale: locale) } }
    public var symbol: String { switch self { case .messages: "bubble.left.and.bubble.right"; case .groups: "person.3"; case .agents: "sparkles"; case .more: "ellipsis" } }
}
public enum AppRoute: Hashable, Sendable {
    /// A group's conversation: the conversation id, the SDK `group_id` (they can differ) and the title to show.
    case conversation(String), groupConversation(String, group: String, title: String?), contacts, strangers, contact(String)
    case settings, devices, device(String), nodes, node(String), appearance, privacy, appLock, backup, account, about
    case systemPermissions
    /// The Username page: the account's directory status and the claim or change of the name.
    case username
    /// The Settings page that shows how messages reach this phone.
    case delivery
    case calls(String?)
    /// Media storage of the active account on this device.
    case mediaStorage
    case permissions, tasks, linkDevice, pairDevice, recoverAccount, onboarding, notices, shellNavigation
    /// Unlock of an account this device knows (created or restored here) that the SDK has not opened.
    case unlockAccount(String)
    public static func parse(_ url: URL) -> Self? {
        guard url.scheme == "ramflux", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host == "conversation", let id = parts.first, parts.count == 1,
           !id.isEmpty, id.utf8.count <= 256 { return .conversation(id) }
        if url.host == "settings", parts.isEmpty { return .settings }
        return nil
    }
}
