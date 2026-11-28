// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Navigation adapter only; all asynchronous work belongs to AppShellViewModel.
public struct AppShellHost: View {
    @Environment(\.locale) private var locale
    @Bindable public var coordinator: AppShellCoordinator
    private let tabContent: (AppTab, String?) -> AnyView?
    private let destination: (AppRoute) -> AnyView
    private let lockPage: ((AccountRecord) -> AnyView)?
    public init(coordinator: AppShellCoordinator, tabContent: @escaping (AppTab, String?) -> AnyView? = { _, _ in nil }, lockPage: ((AccountRecord) -> AnyView)? = nil, destination: @escaping (AppRoute) -> AnyView = { _ in AnyView(RFUnavailableView(title: FeatureAppShellStrings.text("common.appName"), message: UnavailableReason.featureNotInstalled.message)) }) { self.coordinator = coordinator; self.destination = destination; self.tabContent = tabContent; self.lockPage = lockPage }
    public var body: some View {
        NavigationStack(path: $coordinator.path) {
            AppShellScreen(state: coordinator.viewModel.state, onAction: coordinator.send, featureContent: tabContent(coordinator.viewModel.state.tab, coordinator.viewModel.state.session.activeAccountID), lockPage: lockPage)
                .rfHidesNavigationBar()
                .navigationDestination(for: AppRoute.self) { route in
                    // One header per screen: the kit header is the only one, so the system bar is hidden on every route
                    // (the interactive pop gesture is kept by RFPresentation).
                    destination(route).rfHidesNavigationBar()
                }
        }.sheet(item: $coordinator.sheet) { _ in
            AccountPickerScreen(state: coordinator.viewModel.state, onAction: coordinator.send)
        }
    }
    private func title(_ route: AppRoute) -> String {
        switch route { case .settings: FeatureAppShellStrings.text("settings.title", locale: locale); case .conversation: FeatureAppShellStrings.text("shell.conversation.title", locale: locale); case .devices: FeatureAppShellStrings.text("settings.devices.title", locale: locale); case .contacts: FeatureAppShellStrings.text("common.tab.contacts", locale: locale); default: FeatureAppShellStrings.text("common.appName", locale: locale) }
    }
}
