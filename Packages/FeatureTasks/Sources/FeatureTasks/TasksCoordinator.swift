// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class TasksCoordinator {
    public let viewModel: TasksViewModel
    public init(repository: any TasksRepository, conversations: any ConversationsRepository, account: String, mode: TasksMode = .conversations, onEvent: @escaping (TasksEvent) -> Void = { _ in }) { viewModel = TasksViewModel(repository: repository, conversations: conversations, account: account, state: TasksState(mode: mode), emit: onEvent) }
    public func send(_ action: TasksAction) { viewModel.send(action) }
}
