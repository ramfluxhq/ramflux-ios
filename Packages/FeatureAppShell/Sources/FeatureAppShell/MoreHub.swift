// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

public enum MoreHubItem: Equatable, Sendable {
    case route(AppRoute)
    case navigation
    case accounts

    public var titleKey: String {
        switch self {
        case .route(.contacts): "common.nav.contacts"
        case .route(.tasks): "common.nav.tasks"
        case .route(.permissions): "common.perm.title"
        case .route(.settings): "common.nav.settings"
        case .route(.notices): "shell.notices.title"
        case .route(.calls): "shell.more.calls"
        case .navigation: "shell.more.navigation"
        case .accounts: "shell.accounts.title"
        case .route: "common.nav.settings"
        }
    }

    public var previewKey: String {
        switch self {
        case .route(.contacts): "settings.more.hub.contacts.preview"
        case .route(.tasks): "settings.more.hub.tasks.preview"
        case .route(.permissions): "settings.more.hub.access.preview"
        case .route(.settings): "settings.more.hub.settings.preview"
        case .route(.notices): "shell.notices.preview"
        case .route(.calls): "shell.more.calls.preview"
        case .navigation: "shell.more.navigation.detail"
        case .accounts: "shell.accounts.preview"
        case .route: "settings.more.hub.settings.preview"
        }
    }

    var icon: String {
        switch self {
        case .route(.contacts): "contact"
        case .route(.tasks): "clipboard-list"
        case .route(.permissions): "shield"
        case .route(.settings): "settings"
        case .route(.notices): "file-text"
        case .route(.calls): "phone"
        case .navigation: "sliders-horizontal"
        case .accounts: "user-round"
        case .route: "settings"
        }
    }

    var tag: String {
        switch self {
        case .route(.calls): "more-calls"
        case .route(let route): "more-\(String(describing: route))"
        case .navigation: "shell-more-navigation"
        case .accounts: "more-accounts"
        }
    }
}

public enum MoreHub {
    /// Designed G01 rows, then call history, the account picker and the font notices.
    /// Call history, the account picker and notices have no board yet.
    public static func items(order: String = ShellShortcuts.defaultOrder, hidden: String = "") -> [MoreHubItem] {
        let shortcuts: [MoreHubItem] = ShellShortcuts.moreIds(order: order, hidden: hidden).map { id in
            id == "tasks" ? .route(.tasks) : .route(.contacts)
        }
        return shortcuts + [
            .route(.permissions), .route(.settings), .navigation, .route(.calls(nil)), .accounts, .route(.notices),
        ]
    }
}

public struct MoreHubScreen: View {
    @Environment(\.locale) private var locale
    @Binding var order: String
    @Binding var hidden: String
    public let onAction: (AppShellAction) -> Void

    public init(
        order: Binding<String> = .constant(ShellShortcuts.defaultOrder),
        hidden: Binding<String> = .constant(""),
        onAction: @escaping (AppShellAction) -> Void
    ) {
        self._order = order
        self._hidden = hidden
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            KitPageHeader(AppTab.more.title(locale: locale), large: true, tag: "more-header")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(MoreHub.items(order: order, hidden: hidden).enumerated()), id: \.offset) { _, item in
                        MoreHubRow(
                            title: FeatureAppShellStrings.text(item.titleKey, locale: locale),
                            summary: FeatureAppShellStrings.text(item.previewKey, locale: locale),
                            icon: item.icon,
                            tag: item.tag,
                            action: { open(item) }
                        )
                    }
                }
                .padding(.top, 20)
            }
        }
        .shellHidesSystemBar()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("more-hub")
    }

    private func open(_ item: MoreHubItem) {
        switch item {
        case .accounts: onAction(.openAccounts)
        case .navigation: onAction(.open(.shellNavigation))
        case .route(let route): onAction(.open(route))
        }
    }
}

/// G01 rows are hand-built: 70 high, a 44 circle, a 22 glyph, and a 16 chevron.
/// KitRow stays 58 with a 30 tile so the kit evidence frame does not move.
private struct MoreHubRow: View {
    var title: String
    var summary: String
    var icon: String
    var tag: String
    var action: () -> Void
    @Environment(\.rfTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: KitMetrics.rowGap) {
                KitIcon(name: icon, size: 22, tint: theme.text)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
                VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                    Text(title)
                        .rfFont(.size(theme.size_mobile_body), weight: .semibold)
                        .foregroundStyle(theme.text)
                    if !summary.isEmpty {
                        Text(summary)
                            .rfFont(.size(theme.size_body))
                            .foregroundStyle(theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KitIcon(name: "chevron-right", size: KitMetrics.glyph16, tint: theme.control)
            }
            .padding(.horizontal, KitMetrics.gutter)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tag)
        .accessibilityLabel(title)
    }
}

extension View {
    func shellHidesSystemBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
