// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class ConversationsCoordinator {
    public let viewModel: ConversationsViewModel
    public init(repository: any ConversationsRepository, account: String, navigate: @escaping (AppRoute) -> Void) {
        viewModel = ConversationsViewModel(repository: repository, account: account) { event in if case .navigate(let route) = event { navigate(route) } }
    }
    public func send(_ action: ConversationsAction) { viewModel.send(action) }
}
