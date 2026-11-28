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
    private let lockPage: ((AccountRecord) -> AnyView)?
    public let onAction: (AppShellAction) -> Void
    public init(state: AppShellState, onAction: @escaping (AppShellAction) -> Void, featureContent: AnyView? = nil, lockPage: ((AccountRecord) -> AnyView)? = nil) {
        self.state = state
        self.onAction = onAction
        self.featureContent = featureContent
        self.lockPage = lockPage
    }
    /// The account whose lock page replaces the tabs: no account is open and the SDK lists a locked one.
    private var lockedAccount: AccountRecord? {
        guard state.session.phase == .ready, state.session.activeAccountID == nil else { return nil }
        return state.session.accounts.first(where: \.isLocked)
    }

    public var body: some View {
        RFPage {
            if state.privacyShield {
                Text(FeatureAppShellStrings.text("common.appName", locale: locale))
                    .rfFont(.page)
                    .accessibilityLabel(FeatureAppShellStrings.text("shell.locked.accessibility", locale: locale))
            } else if let account = lockedAccount, let lockPage {
                lockPage(account)
            } else {
                VStack(spacing: 0) {
                    if let featureContent {
                        featureContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholder
                    }
                    KitTabBar(tabs: AppTab.allCases.map(kitTab), selected: selectedIndex, onSelect: select, tag: "shell-tabs")
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .privacySensitive()
        // A screen identifier on a plain container replaces its children's own identifiers; containing keeps them.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-shell")
    }

    private var placeholder: some View {
        VStack(spacing: 0) {
            KitPageHeader(state.tab.title(locale: locale), large: true, tag: "shell-header")
            ScrollView {
                VStack(alignment: .leading, spacing: KitMetrics.rowGap) {
                    sessionStatus
                    if state.session.activeAccountID == nil, state.session.phase == .ready {
                        KitButton(FeatureAppShellStrings.text("shell.accounts.title", locale: locale), action: { onAction(.openAccounts) }, kind: .primary, tag: "shell-accounts")
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
        case .agents: KitTab(icon: "bot", label: tab.title(locale: locale), hitTag: "tab-agents")
        case .more: KitTab(icon: "ellipsis", label: tab.title(locale: locale), hitTag: "tab-more")
        }
    }

    @ViewBuilder private var sessionStatus: some View {
        switch state.session.phase {
        case .opening:
            ProgressView(FeatureAppShellStrings.text("shell.loading.accountServices", locale: locale))
        case .ready:
            if let account = state.session.activeAccountID {
                LabeledContent(FeatureAppShellStrings.text("shell.session.account", locale: locale)) {
                    Text(untrusted: (state.session.accounts.first { $0.id == account } ?? AccountRecord(id: account, displayName: "", isLocked: false)).title(locale: locale))
                }
            } else if state.session.accounts.contains(where: \.isLocked) {
                EmptyView()
            } else {
                emptyBlock(
                    title: FeatureAppShellStrings.text("shell.noAccount.title", locale: locale),
                    body: FeatureAppShellStrings.text("common.appName", locale: locale),
                    icon: "user-round"
                )
            }
        case .unavailable(let reason):
            emptyBlock(
                title: FeatureAppShellStrings.text("shell.unavailable.title", locale: locale),
                body: reason.message(locale: locale),
                icon: "circle-alert"
            )
        case .failed(let failure):
            failureView(failure)
        case .stopped, .suspended:
            Text(FeatureAppShellStrings.text("shell.stopped.title", locale: locale))
        }
    }

    private func emptyBlock(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
            KitStatusHero(icon: icon, tag: "shell-empty")
            Text(title).rfFont(.body, weight: .semibold).foregroundStyle(theme.text)
            Text(body).rfFont(.caption).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureView(_ failure: AppFailure) -> some View {
        RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale), retry: failure.canRetry ? { onAction(.retry) } : nil)
    }
}
