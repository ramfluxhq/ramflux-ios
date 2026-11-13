// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class AgentsCoordinator {
    public let viewModel: AgentsViewModel
    public init(repository: any AgentsRepository, account: String, onEvent: @escaping (AgentsEvent) -> Void = { _ in }) { viewModel = AgentsViewModel(repository: repository, account: account, emit: onEvent) }
    public func send(_ action: AgentsAction) { viewModel.send(action) }
}
