// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
import FeatureCards

/// Agent surfaces in the timeline: read through `surface.list` (following `next_cursor`, at most
/// `cardPages` pages, so the in-memory set stays bounded) when the chat appears and when the
/// account changes, drawn under the message that carried them, and acted on with the shown
/// version and hash. A retry of the same button reuses its action message id.
extension ChatViewModel {
    static let cardPages = 5

    func handleCards(_ action: ChatAction) {
        switch action {
        case .surfaceInput(let ref, let pointer, let value):
            guard let key = cardKey(ref), state.cards[key]?.surface.actionable == true, pointer.hasPrefix("/") || pointer.isEmpty else { return }
            state.cards[key]?.drafts[pointer] = value
        case .surfaceButton(let ref, let button): act(ref, button: button)
        default: break
        }
    }

    func loadCards() {
        guard cardsTask == nil else { cardsPending = true; return }
        let current = epoch
        cardsTask = Task { [weak self, cards, account, conversation] in
            var found: [SurfaceRecord] = [], cursor: String?, failure: AppFailure?
            for _ in 0..<Self.cardPages {
                switch await cards.surfaces(account: account, conversation: conversation, cursor: cursor) {
                case .success(let page): found += page.surfaces; cursor = page.nextCursor
                case .failure(let error): failure = error
                }
                if failure != nil || cursor == nil || Task.isCancelled { break }
            }
            guard let self, self.epoch == current, !Task.isCancelled else { return }
            self.cardsTask = nil
            // A cards repository that is not connected leaves the timeline as it is.
            if failure == nil {
                var next: [String: SurfaceCardState] = [:]
                for surface in found {
                    guard let message = surface.messageID else { continue }
                    let previous = self.state.cards[message]
                    // Drafts survive a refresh only while the surface is the same version.
                    let drafts = previous?.surface.version == surface.version ? previous?.drafts ?? [:] : [:]
                    next[message] = SurfaceCardState(surface: surface, drafts: drafts, sending: previous?.sending ?? false, failure: previous?.failure)
                }
                self.state.cards = next
            }
            if self.cardsPending { self.cardsPending = false; self.loadCards() }
        }
    }

    func stopCards() { cardsTask?.cancel(); cardsTask = nil; cardsPending = false; cardActions = [:]; state.cards = [:] }

    private func cardKey(_ ref: String) -> String? { state.cards.first { $0.value.surface.surfaceRef == ref }?.key }

    private func act(_ ref: String, button: String) {
        guard let key = cardKey(ref), let card = state.cards[key], card.surface.actionable, !card.sending else { return }
        let attempt = ref + "\u{0}" + button + "\u{0}" + String(card.surface.version)
        let messageID = cardActions[attempt] ?? NativeCardsRepository.newActionMessageID()
        cardActions[attempt] = messageID
        state.cards[key]?.sending = true; state.cards[key]?.failure = nil
        let current = epoch
        Task { [weak self, cards, account] in
            let result = await cards.act(account: account, shown: card.surface, buttonID: button, drafts: card.drafts, messageID: messageID)
            guard let self, self.epoch == current else { return }
            self.state.cards[key]?.sending = false
            switch result {
            case .success(let outcome) where outcome.accepted || outcome.queued:
                self.cardActions[attempt] = nil; self.state.cards[key]?.drafts = [:]
            case .success(let outcome): self.state.cards[key]?.failure = .typedRefusal(outcome.reasonCode ?? "not_permitted"); self.cardActions[attempt] = nil
            case .failure(let error):
                self.state.cards[key]?.failure = error
                // A refusal tied to this version cannot succeed again with the same id.
                if case .typedRefusal = error { self.cardActions[attempt] = nil }
            }
            self.loadCards()
        }
    }
}
