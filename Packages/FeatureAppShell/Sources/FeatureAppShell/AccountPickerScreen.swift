// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Navigation adapter only; all asynchronous work belongs to AppShellViewModel.
public struct AccountPickerScreen: View {
    public let state: AppShellState
    public let onAction: (AppShellAction) -> Void
    public init(state: AppShellState, onAction: @escaping (AppShellAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage {
            if state.session.accounts.isEmpty {
                RFUnavailableView(title: "No open accounts", message: "Account setup and unlock belong to the onboarding module.")
            } else {
                List(state.session.accounts) { account in
                    Button(account.displayName) { onAction(.selectAccount(account.id)) }.disabled(state.busy)
                }.scrollContentBackground(.hidden)
            }
        }.navigationTitle("Accounts")
    }
}
