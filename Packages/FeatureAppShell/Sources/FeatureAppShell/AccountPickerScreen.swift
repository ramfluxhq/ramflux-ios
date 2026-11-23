// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Navigation adapter only; all asynchronous work belongs to AppShellViewModel.
public struct AccountPickerScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: AppShellState
    public let onAction: (AppShellAction) -> Void
    public init(state: AppShellState, onAction: @escaping (AppShellAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage {
            VStack(spacing: theme.gap) {
                Button(FeatureAppShellStrings.text("account.add", locale: locale)) { onAction(.open(.onboarding)) }.disabled(state.busy)
                if state.session.accounts.isEmpty {
                    RFUnavailableView(title: FeatureAppShellStrings.text("shell.accounts.empty.title", locale: locale), message: FeatureAppShellStrings.text("shell.accounts.empty.message", locale: locale))
                } else {
                    List(state.session.accounts) { account in
                        Button { onAction(account.isLocked ? .unlockAccount(account.id) : .selectAccount(account.id)) } label: {
                            HStack {
                                Text(untrusted: account.displayName)
                                Spacer(minLength: theme.gap)
                                if account.isLocked { Text(FeatureAppShellStrings.text("shell.accounts.locked", locale: locale)).foregroundStyle(theme.secondary) }
                            }
                        }
                        .disabled(state.busy)
                        .accessibilityIdentifier("account-" + account.id)
                    }.scrollContentBackground(.hidden)
                }
            }.padding(theme.gap)
        }.navigationTitle(FeatureAppShellStrings.text("shell.accounts.title", locale: locale))
    }
}
