// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class ChatCoordinator {
    public let viewModel: ChatViewModel
    public init(repository: any ChatRepository, cards: any CardsRepository = UnavailableCardsRepository(), account: String, conversation: String, isGroup: Bool = false, groupID: String? = nil, title: String? = nil, onEvent: @escaping (ChatEvent) -> Void = { _ in }) { viewModel = ChatViewModel(repository: repository, cards: cards, account: account, conversation: conversation, isGroup: isGroup, groupID: groupID, title: title, emit: onEvent) }
    public func send(_ action: ChatAction) { viewModel.send(action) }
}
