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
        case .navigation: "shell.more.navigation"
        case .accounts: "copy.8a7c8b67fe8b"
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
        case .navigation: "sliders-horizontal"
        case .accounts: "user-round"
        case .route: "settings"
        }
    }

    var tag: String {
        switch self {
        case .route(let route): "more-\(String(describing: route))"
        case .navigation: "shell-more-navigation"
        case .accounts: "more-accounts"
        }
    }
}

public enum MoreHub {
    /// Designed G01 rows, then the account picker and the font notices.
    /// The account picker and notices have no board yet.
    public static func items(order: String = ShellShortcuts.defaultOrder, hidden: String = "") -> [MoreHubItem] {
        let shortcuts: [MoreHubItem] = ShellShortcuts.moreIds(order: order, hidden: hidden).map { id in
            id == "tasks" ? .route(.tasks) : .route(.contacts)
        }
        return shortcuts + [
            .route(.permissions), .route(.settings), .navigation, .accounts, .route(.notices),
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
                VStack(spacing: 0) {
                    ForEach(Array(MoreHub.items(order: order, hidden: hidden).enumerated()), id: \.offset) { _, item in
                        KitRow(
                            FeatureAppShellStrings.text(item.titleKey, locale: locale),
                            action: { open(item) },
                            icon: item.icon,
                            value: FeatureAppShellStrings.text(item.previewKey, locale: locale),
                            tag: item.tag
                        )
                    }
                }
            }
        }
        .shellHidesSystemBar()
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

extension View {
    func shellHidesSystemBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
