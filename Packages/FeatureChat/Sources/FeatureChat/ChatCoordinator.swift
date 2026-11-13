// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class ChatCoordinator {
    public let viewModel: ChatViewModel
    public init(repository: any ChatRepository, account: String, conversation: String, isGroup: Bool = false, title: String? = nil, onEvent: @escaping (ChatEvent) -> Void = { _ in }) { viewModel = ChatViewModel(repository: repository, account: account, conversation: conversation, isGroup: isGroup, title: title, emit: onEvent) }
    public func send(_ action: ChatAction) { viewModel.send(action) }
}
