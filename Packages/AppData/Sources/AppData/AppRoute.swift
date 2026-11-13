// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case messages, groups, agents, more
    public var id: Self { self }
    public var title: String { title(locale: .current) }
    public func title(locale: Locale) -> String { switch self { case .messages: AppDataStrings.text("copy.04d7b4833927", locale: locale); case .groups: AppDataStrings.text("copy.39bbb719fa2b", locale: locale); case .agents: AppDataStrings.text("copy.279b44d2ab4b", locale: locale); case .more: AppDataStrings.text("copy.d47d7cb0e4f8", locale: locale) } }
    public var symbol: String { switch self { case .messages: "bubble.left.and.bubble.right"; case .groups: "person.3"; case .agents: "sparkles"; case .more: "ellipsis" } }
}
public enum AppRoute: Hashable, Sendable {
    case conversation(String), contacts, strangers, contact(String), safetyNumber(String)
    case settings, devices, device(String), nodes, node(String), appearance, privacy, backup, account, about
    case permissions, tasks, linkDevice, recoverAccount, onboarding
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
