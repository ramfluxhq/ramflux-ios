// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Navigation adapter only; all asynchronous work belongs to AppShellViewModel.
public struct AppShellHost: View {
    @Bindable public var coordinator: AppShellCoordinator
    public init(coordinator: AppShellCoordinator) { self.coordinator = coordinator }
    public var body: some View {
        NavigationStack(path: $coordinator.path) {
            AppShellScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
                .navigationDestination(for: AppRoute.self) { route in
                    RFUnavailableView(title: title(route), message: UnavailableReason.featureNotInstalled.message)
                }
        }.sheet(item: $coordinator.sheet) { _ in
            AccountPickerScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        }
    }
    private func title(_ route: AppRoute) -> String {
        switch route { case .settings: "Settings"; case .conversation: "Conversation"; case .devices: "My devices"; case .contacts: "Contacts"; default: "Ramflux" }
    }
}
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
