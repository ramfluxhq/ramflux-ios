// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class ContactsCoordinator {
    public let viewModel: ContactsViewModel
    public init(repository: any ContactsRepository, account: String, mode: ContactsMode = .contacts, navigate: @escaping (AppRoute) -> Void) {
        viewModel = ContactsViewModel(repository: repository, account: account, state: ContactsState(mode: mode)) { event in if case .navigate(let route) = event { navigate(route) } }
    }
    public func send(_ action: ContactsAction) { viewModel.send(action) }
}
