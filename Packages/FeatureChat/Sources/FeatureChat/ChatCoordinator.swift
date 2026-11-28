// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
import FeatureCards
@MainActor public final class ChatCoordinator {
    public let viewModel: ChatViewModel
    public init(repository: any ChatRepository, cards: any CardsRepository = UnavailableCardsRepository(), identity: any ContactIdentityRepository = UnavailableContactIdentityRepository(), peerContact: String? = nil, account: String, conversation: String, isGroup: Bool = false, groupID: String? = nil, title: String? = nil, peerIsAgent: Bool = false, onEvent: @escaping (ChatEvent) -> Void = { _ in }) { viewModel = ChatViewModel(repository: repository, cards: cards, identity: identity, peerContact: peerContact, account: account, conversation: conversation, isGroup: isGroup, groupID: groupID, title: title, peerIsAgent: peerIsAgent, emit: onEvent) }
    public func send(_ action: ChatAction) { viewModel.send(action) }
    /// Where the conversation's cards read their images: the object API of this account, through the cards repository.
    public var cardImages: CardImageProvider {
        let cards = viewModel.cards, account = viewModel.account
        return CardImageProvider { ref, attachment in await cards.image(account: account, surfaceRef: ref, attachment: attachment) }
    }
}
