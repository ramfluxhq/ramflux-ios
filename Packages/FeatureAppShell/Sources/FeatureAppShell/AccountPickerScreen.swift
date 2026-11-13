// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Navigation adapter only; all asynchronous work belongs to AppShellViewModel.
public struct AccountPickerScreen: View {
    @Environment(\.locale) private var locale
    public let state: AppShellState
    public let onAction: (AppShellAction) -> Void
    public init(state: AppShellState, onAction: @escaping (AppShellAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage {
            if state.session.accounts.isEmpty {
                RFUnavailableView(title: FeatureAppShellStrings.text("copy.79b40467bd3e", locale: locale), message: FeatureAppShellStrings.text("copy.555b840fbf7c", locale: locale))
            } else {
                List(state.session.accounts) { account in
                    Button(account.displayName) { onAction(.selectAccount(account.id)) }.disabled(state.busy)
                }.scrollContentBackground(.hidden)
            }
        }.navigationTitle(FeatureAppShellStrings.text("copy.8a7c8b67fe8b", locale: locale))
    }
}
