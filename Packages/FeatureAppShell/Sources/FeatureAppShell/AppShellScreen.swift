// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Pure rendering: no SDK imports, tasks, repositories, or state mutation.
public struct AppShellScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: AppShellState
    private let featureContent: AnyView?
    public let onAction: (AppShellAction) -> Void
    public init(state: AppShellState, onAction: @escaping (AppShellAction) -> Void, featureContent: AnyView? = nil) {
        self.state = state
        self.onAction = onAction
        self.featureContent = featureContent
    }

    public var body: some View {
        RFPage {
            if state.privacyShield {
                Text(FeatureAppShellStrings.text("copy.28f2d4300544", locale: locale))
                    .font(theme.pageFont)
                    .accessibilityLabel(FeatureAppShellStrings.text("copy.7a9453b18943", locale: locale))
            } else {
                VStack(spacing: 0) {
                    if let featureContent {
                        featureContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholder
                    }
                    KitTabBar(tabs: AppTab.allCases.map(kitTab), selected: selectedIndex, onSelect: select, tag: "shell-tabs")
                }
            }
        }
        .privacySensitive()
        .accessibilityIdentifier("app-shell")
    }

    private var placeholder: some View {
        VStack(spacing: 0) {
            KitPageHeader(state.tab.title(locale: locale), large: true, latin: state.tab == .agents, tag: "shell-header")
            ScrollView {
                VStack(alignment: .leading, spacing: KitMetrics.rowGap) {
                    sessionStatus
                    if state.session.activeAccountID == nil, state.session.phase == .ready {
                        KitButton(FeatureAppShellStrings.text("copy.8a7c8b67fe8b", locale: locale), action: { onAction(.openAccounts) }, tag: "shell-accounts")
                    }
                    if let failure = state.failure { failureView(failure) }
                }
                .padding(KitMetrics.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectedIndex: Int { AppTab.allCases.firstIndex(of: state.tab) ?? 0 }

    private func select(_ index: Int) {
        let tabs = AppTab.allCases
        guard tabs.indices.contains(index) else { return }
        onAction(.selectTab(tabs[index]))
    }

    private func kitTab(_ tab: AppTab) -> KitTab {
        switch tab {
        case .messages: KitTab(icon: "messages-square", label: tab.title(locale: locale), hitTag: "tab-messages")
        case .groups: KitTab(icon: "users-round", label: tab.title(locale: locale), hitTag: "tab-groups")
        case .agents: KitTab(icon: "bot", label: tab.title(locale: locale), latin: true, hitTag: "tab-agents")
        case .more: KitTab(icon: "ellipsis", label: tab.title(locale: locale), hitTag: "tab-more")
        }
    }

    @ViewBuilder private var sessionStatus: some View {
        switch state.session.phase {
        case .opening:
            ProgressView(FeatureAppShellStrings.text("copy.446531641e6a", locale: locale))
        case .ready:
            if let account = state.session.activeAccountID {
                LabeledContent(FeatureAppShellStrings.text("copy.7e1b0d5641f2", locale: locale), value: account)
            } else {
                emptyBlock(
                    title: FeatureAppShellStrings.text("copy.eab0ba7f342e", locale: locale),
                    body: FeatureAppShellStrings.text("copy.28f2d4300544", locale: locale),
                    icon: "user-round"
                )
            }
        case .unavailable(let reason):
            emptyBlock(
                title: FeatureAppShellStrings.text("copy.9882e82fed9b", locale: locale),
                body: reason.message(locale: locale),
                icon: "circle-alert"
            )
        case .failed(let failure):
            failureView(failure)
        case .stopped, .suspended:
            Text(FeatureAppShellStrings.text("copy.cf60a4dcdd09", locale: locale))
        }
    }

    private func emptyBlock(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
            KitStatusHero(icon: icon, tag: "shell-empty")
            Text(title).font(theme.bodyFont.weight(.semibold)).foregroundStyle(theme.text)
            Text(body).font(theme.captionFont).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureView(_ failure: AppFailure) -> some View {
        RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale), retry: failure.canRetry ? { onAction(.retry) } : nil)
    }
}
