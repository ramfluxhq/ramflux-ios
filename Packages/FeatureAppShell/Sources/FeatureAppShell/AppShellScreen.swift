// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Pure rendering: no SDK imports, tasks, repositories, or state mutation.
public struct AppShellScreen: View {
    @Environment(\.colorScheme) private var scheme
    public let state: AppShellState
    public let onAction: (AppShellAction) -> Void
    public init(state: AppShellState, onAction: @escaping (AppShellAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage {
            if state.privacyShield { Text("Ramflux").font(RFTheme.adaptive(scheme).pageFont).accessibilityLabel("Ramflux is locked") }
            else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: RFTheme.adaptive(scheme).gap) {
                            sessionStatus
                            Button("Set up this phone") { onAction(.open(.onboarding)) }
                            Text(state.tab.title).font(RFTheme.adaptive(scheme).pageFont).accessibilityAddTraits(.isHeader)
                            RFStateBlock(title: state.tab.title, description: state.unavailableFeature.message, kind: .empty,
                                         theme: RFTheme.adaptive(scheme)) { EmptyView() }
                            if let failure = state.failure { failureView(failure) }
                        }.padding().frame(maxWidth: RFTheme.adaptive(scheme).column_max, alignment: .leading).frame(maxWidth: .infinity)
                    }
                    Divider()
                    tabs
                }
            }
        }.privacySensitive().accessibilityIdentifier("app-shell")
    }
    private var header: some View {
        HStack {
            Text("Ramflux").font(.headline)
            Spacer()
            Button("Accounts", systemImage: "person.crop.circle") { onAction(.openAccounts) }.disabled(state.busy)
            Button("Settings", systemImage: "gearshape") { onAction(.open(.settings)) }
        }.padding()
    }
    @ViewBuilder private var sessionStatus: some View {
        switch state.session.phase {
        case .opening: ProgressView("Opening account services")
        case .ready:
            if let account = state.session.activeAccountID { LabeledContent("Account", value: account) }
            else { Text("Choose an account or set up this phone when onboarding is available.") }
        case .unavailable(let reason):
            RFStateBlock(title: "Account services unavailable", description: reason.message, kind: .empty, theme: RFTheme.adaptive(scheme)) { EmptyView() }
        case .failed(let failure): failureView(failure)
        case .stopped, .suspended: Text("Account services are stopped")
        }
    }
    private func failureView(_ failure: AppFailure) -> some View {
        RFFailureView(title: failure.title, message: failure.message, retry: failure.canRetry ? { onAction(.retry) } : nil)
    }
    private var tabs: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ForEach(AppTab.allCases) { tab in tabButton(tab, vertical: true) } }
            ScrollView(.horizontal) { HStack { ForEach(AppTab.allCases) { tab in tabButton(tab, vertical: false) } } }
        }.padding(.horizontal).background(RFTheme.adaptive(scheme).nav)
    }
    private func tabButton(_ tab: AppTab, vertical: Bool) -> some View {
        Button { onAction(.selectTab(tab)) } label: {
            Group {
                if vertical { VStack { Image(systemName: tab.symbol); Text(tab.title) } }
                else { Label(tab.title, systemImage: tab.symbol) }
            }.frame(maxWidth: .infinity, minHeight: 52)
        }.buttonStyle(.plain).foregroundStyle(state.tab == tab ? RFTheme.adaptive(scheme).text : RFTheme.adaptive(scheme).secondary)
            .accessibilityAddTraits(state.tab == tab ? .isSelected : [])
            .accessibilityIdentifier("tab-" + tab.rawValue)
    }
}
