// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class ConversationsCoordinator {
    public let viewModel: ConversationsViewModel
    public init(repository: any ConversationsRepository, identity: any ContactIdentityRepository = UnavailableContactIdentityRepository(), account: String, accountTitle: String = "", navigate: @escaping (AppRoute) -> Void) {
        viewModel = ConversationsViewModel(repository: repository, identity: identity, account: account, accountTitle: accountTitle) { event in if case .navigate(let route) = event { navigate(route) } }
    }
    public func send(_ action: ConversationsAction) { viewModel.send(action) }
}
