// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class GroupsCoordinator {
    public let viewModel: GroupsViewModel
    public init(repository: any GroupsRepository, contacts: any ContactsRepository, account: String, onEvent: @escaping (GroupsEvent) -> Void = { _ in }) { viewModel = GroupsViewModel(repository: repository, contacts: contacts, account: account, emit: onEvent) }
    public func send(_ action: GroupsAction) { viewModel.send(action) }
}
