// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

public enum MoreHubItem: Equatable, Sendable {
    case route(AppRoute)
    case accounts

    public var titleKey: String {
        switch self {
        case .route(.contacts): "common.nav.contacts"
        case .route(.tasks): "common.nav.tasks"
        case .route(.permissions): "common.perm.title"
        case .route(.settings): "common.nav.settings"
        case .route(.notices): "shell.notices.title"
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
        case .accounts: "shell.accounts.preview"
        case .route: "settings.more.hub.settings.preview"
        }
    }

    var tag: String {
        switch self {
        case .route(let route): "more-\(String(describing: route))"
        case .accounts: "more-accounts"
        }
    }
}

public enum MoreHub {
    /// Designed G01 rows, then the account picker and the font notices.
    /// The account picker and notices have no board yet.
    public static let items: [MoreHubItem] = [
        .route(.contacts), .route(.tasks), .route(.permissions), .route(.settings),
        .accounts, .route(.notices),
    ]
}

public struct MoreHubScreen: View {
    @Environment(\.locale) private var locale
    public let onAction: (AppShellAction) -> Void
    public init(onAction: @escaping (AppShellAction) -> Void) { self.onAction = onAction }

    public var body: some View {
        VStack(spacing: 0) {
            KitPageHeader(AppTab.more.title(locale: locale), large: true, tag: "more-header")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(MoreHub.items.enumerated()), id: \.offset) { _, item in
                        KitRow(
                            FeatureAppShellStrings.text(item.titleKey, locale: locale),
                            action: { open(item) },
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
