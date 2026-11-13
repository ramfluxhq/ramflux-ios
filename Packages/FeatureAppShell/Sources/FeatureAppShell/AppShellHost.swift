// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Navigation adapter only; all asynchronous work belongs to AppShellViewModel.
public struct AppShellHost: View {
    @Bindable public var coordinator: AppShellCoordinator
    private let tabContent: (AppTab, String?) -> AnyView?
    private let destination: (AppRoute) -> AnyView
    public init(coordinator: AppShellCoordinator, tabContent: @escaping (AppTab, String?) -> AnyView? = { _, _ in nil }, destination: @escaping (AppRoute) -> AnyView = { _ in AnyView(RFUnavailableView(title: "Ramflux", message: UnavailableReason.featureNotInstalled.message)) }) { self.coordinator = coordinator; self.destination = destination; self.tabContent = tabContent }
    public var body: some View {
        NavigationStack(path: $coordinator.path) {
            AppShellScreen(state: coordinator.viewModel.state, onAction: coordinator.send, featureContent: tabContent(coordinator.viewModel.state.tab, coordinator.viewModel.state.session.activeAccountID))
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }.sheet(item: $coordinator.sheet) { _ in
            AccountPickerScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        }
    }
    private func title(_ route: AppRoute) -> String {
        switch route { case .settings: "Settings"; case .conversation: "Conversation"; case .devices: "My devices"; case .contacts: "Contacts"; default: "Ramflux" }
    }
}
