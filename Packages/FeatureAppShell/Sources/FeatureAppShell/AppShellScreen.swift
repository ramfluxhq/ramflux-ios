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
    public init(state: AppShellState, onAction: @escaping (AppShellAction) -> Void, featureContent: AnyView? = nil) { self.state = state; self.onAction = onAction; self.featureContent = featureContent }
    public var body: some View {
        RFPage {
            if state.privacyShield { Text(FeatureAppShellStrings.text("copy.28f2d4300544", locale: locale)).font(theme.pageFont).accessibilityLabel(FeatureAppShellStrings.text("copy.7a9453b18943", locale: locale)) }
            else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    if let featureContent {
                        featureContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: theme.gap) {
                                sessionStatus
                                Button(FeatureAppShellStrings.text("copy.b5305ec41049", locale: locale)) { onAction(.open(.onboarding)) }
                                Text(state.tab.title(locale: locale)).font(theme.pageFont).accessibilityAddTraits(.isHeader)
                                RFStateBlock(title: state.tab.title(locale: locale), description: state.unavailableFeature.message(locale: locale), kind: .empty, theme: theme) { EmptyView() }
                                if let failure = state.failure { failureView(failure) }
                            }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity)
                        }
                    }
                    Divider()
                    tabs
                }
            }
        }.privacySensitive().accessibilityIdentifier("app-shell")
    }
    private var header: some View {
        HStack {
            Text(FeatureAppShellStrings.text("copy.28f2d4300544", locale: locale)).font(theme.bodyFont.weight(.semibold))
            Spacer()
            Button(FeatureAppShellStrings.text("copy.8a7c8b67fe8b", locale: locale), systemImage: "person.crop.circle") { onAction(.openAccounts) }.disabled(state.busy)
            Button(FeatureAppShellStrings.text("copy.74a883a037bc", locale: locale), systemImage: "gearshape") { onAction(.open(.settings)) }
        }.padding(theme.gap)
    }
    @ViewBuilder private var sessionStatus: some View {
        switch state.session.phase {
        case .opening: ProgressView(FeatureAppShellStrings.text("copy.446531641e6a", locale: locale))
        case .ready:
            if let account = state.session.activeAccountID { LabeledContent(FeatureAppShellStrings.text("copy.7e1b0d5641f2", locale: locale), value: account) }
            else { Text(FeatureAppShellStrings.text("copy.eab0ba7f342e", locale: locale)) }
        case .unavailable(let reason):
            RFStateBlock(title: FeatureAppShellStrings.text("copy.9882e82fed9b", locale: locale), description: reason.message, kind: .empty, theme: theme) { EmptyView() }
        case .failed(let failure): failureView(failure)
        case .stopped, .suspended: Text(FeatureAppShellStrings.text("copy.cf60a4dcdd09", locale: locale))
        }
    }
    private func failureView(_ failure: AppFailure) -> some View {
        RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale), retry: failure.canRetry ? { onAction(.retry) } : nil)
    }
    private var tabs: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ForEach(AppTab.allCases) { tab in tabButton(tab, vertical: true) } }
            ScrollView(.horizontal) { HStack { ForEach(AppTab.allCases) { tab in tabButton(tab, vertical: false) } } }
        }.padding(.horizontal, theme.gap).background(theme.nav)
    }
    private func tabButton(_ tab: AppTab, vertical: Bool) -> some View {
        Button { onAction(.selectTab(tab)) } label: {
            Group {
                if vertical { VStack { Image(systemName: tab.symbol); Text(tab.title(locale: locale)) } }
                else { Label(tab.title(locale: locale), systemImage: tab.symbol) }
            }.frame(maxWidth: .infinity, minHeight: 52)
        }.buttonStyle(.plain).foregroundStyle(state.tab == tab ? theme.text : theme.secondary)
            .accessibilityAddTraits(state.tab == tab ? .isSelected : [])
            .accessibilityIdentifier("tab-" + tab.rawValue)
    }
}
