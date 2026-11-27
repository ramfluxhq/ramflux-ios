// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
import FeatureCards
import RamfluxCore

/// Agent cards in the timeline: the cards of the conversation are listed through `surface.list` (following `next_cursor`,
/// at most `cardPages` pages), each one is drawn from its runtime session (`card.session.*`, opened or refreshed here),
/// and host events and slot answers go back through the same session. The sessions of cards that left the window are
/// disposed; the pool keeps the rest within its residency and open limits.
extension ChatViewModel {
    static let cardPages = 5

    func handleCards(_ action: ChatAction) {
        switch action {
        case .cardEvent(let ref, let key, let event): sendEvent(ref, key: key, event: event)
        case .cardAnswer(let ref, let answer): sendAnswer(ref, answer)
        case .cardResync(let ref): resync(ref)
        case .appearance(let dark, let locale): updateAppearance(dark: dark, locale: locale)
        default: break
        }
    }

    func loadCards() {
        guard cardsTask == nil else { cardsPending = true; return }
        let current = epoch
        let locale = cardLocale, dark = cardDark
        cardsTask = Task { [weak self, cards, account, conversation] in
            var found: [CardSurface] = [], cursor: String?, failure: AppFailure?
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
                var next: [String: CardMessageState] = [:]
                // A refreshed card's failure when its refresh started, and the refresh's own outcome.
                var refreshes: [String: (before: AppFailure?, error: AppFailure?)] = [:]
                for surface in found {
                    guard let message = surface.messageID, next[message] == nil else { continue }
                    var card = CardMessageState(surface: surface, display: self.state.cards[message]?.display)
                    // Only the newest cards of the window hold sessions; older ones wait for the list to reach them.
                    if next.count < CardSessionPool.maximumOpen {
                        let before = self.state.cards[message]?.failure
                        // The pool opens the session, or brings it to the listed version (an update only when it moved).
                        switch await cards.refresh(account: account, surface: surface, locale: locale, dark: dark) {
                        case .success(let display): card.display = display; refreshes[message] = (before, nil)
                        case .failure(let error): refreshes[message] = (before, error)
                        }
                    }
                    next[message] = card
                }
                await cards.retain(account: account, surfaceRefs: Set(found.map(\.surfaceRef)))
                // Written last, from the live state: the awaits above let host events, answers and submits of these cards
                // change their pending link, decisions, sending flag and failure, and a copy taken before them would undo
                // that. A card that was not refreshed keeps its live display too.
                var settled: [String: CardMessageState] = [:]
                for (message, staleCard) in next {
                    var card = staleCard
                    let live = self.state.cards[message]
                    card.sending = live?.sending ?? false
                    card.pending = live?.pending
                    card.decided = live?.decided ?? []
                    if refreshes[message] == nil { card.display = live?.display }
                    // A refresh outcome stands unless the card's failure changed while the refresh ran.
                    if let refresh = refreshes[message], live?.failure == refresh.before { card.failure = refresh.error } else { card.failure = live?.failure }
                    // A pending link stays while the runtime still lists its slot; a link whose request has left the tree is
                    // cancelled, so the runtime does not keep waiting for an answer the sheet no longer shows.
                    if case .openURL(_, let requestID, let slotID, let token)? = card.pending,
                       !(card.display?.tree?.hostSlots.contains { $0.id == slotID && $0.requestID == requestID } ?? false) {
                        card.pending = nil
                        Task { _ = await cards.answer(account: account, surfaceRef: card.surface.surfaceRef, token: token, slotID: slotID, requestID: requestID, outcome: .cancel) }
                    }
                    settled[message] = card
                }
                self.state.cards = settled
            }
            if self.cardsPending { self.cardsPending = false; self.loadCards() }
        }
    }

    func stopCards() { cardsTask?.cancel(); cardsTask = nil; cardsPending = false; cardEventsInFlight = [:]; cardsOpening = []; state.cards = [:] }

    private func cardKey(_ ref: String) -> String? { state.cards.first { $0.value.surface.surfaceRef == ref }?.key }

    /// The host's colour scheme and locale. A change re-presents the resident cards in them; the next open takes them too.
    private func updateAppearance(dark: Bool, locale: String) {
        guard dark != cardDark || locale != cardLocale else { return }
        cardDark = dark; cardLocale = locale
        let current = epoch
        for (message, card) in state.cards where card.display?.resident == true {
            let ref = card.surface.surfaceRef
            Task { [weak self, cards, account] in
                let result = await cards.present(account: account, surfaceRef: ref, locale: locale, dark: dark)
                guard let self, self.epoch == current else { return }
                switch result {
                case .success(let display): self.state.cards[message]?.display = display
                case .failure(let error): self.state.cards[message]?.failure = error
                }
            }
        }
    }

    /// Ends one host event or answer of a card. The count never goes below zero: `stopCards` clears it while requests run.
    private func endCardEvent(_ ref: String) {
        let left = (cardEventsInFlight[ref] ?? 0) - 1
        cardEventsInFlight[ref] = left > 0 ? left : nil
    }

    /// Every host event is sent: the card's queue applies them in order (an input merges into a queued input of the same
    /// control), so nothing typed while an earlier event is in flight is dropped.
    private func sendEvent(_ ref: String, key: String, event: CardHostEvent) {
        guard let message = cardKey(ref) else { return }
        // A card that found no place for its session has nothing to send an event to: the tap opens it again.
        if state.cards[message]?.display == nil, let surface = state.cards[message]?.surface { reopen(message, surface: surface); return }
        cardEventsInFlight[ref, default: 0] += 1
        state.cards[message]?.sending = true
        state.cards[message]?.failure = nil
        let current = epoch
        Task { [weak self, cards, account] in
            let result = await cards.event(account: account, surfaceRef: ref, key: key, event: event)
            guard let self else { return }
            self.endCardEvent(ref)
            guard self.epoch == current else { return }
            self.finishCardStep(message, ref: ref, result)
        }
    }

    private func reopen(_ message: String, surface: CardSurface) {
        guard cardsOpening.insert(message).inserted else { return }
        state.cards[message]?.failure = nil
        let current = epoch, locale = cardLocale, dark = cardDark
        Task { [weak self, cards, account] in
            let result = await cards.open(account: account, surface: surface, locale: locale, dark: dark)
            guard let self else { return }
            self.cardsOpening.remove(message)
            guard self.epoch == current else { return }
            switch result {
            case .success(let display): self.state.cards[message]?.display = display
            case .failure(let error): self.state.cards[message]?.failure = error
            }
        }
    }

    private func resync(_ ref: String) {
        let current = epoch
        Task { [weak self, cards, account] in
            _ = await cards.requestResync(account: account, surfaceRef: ref)
            guard let self, self.epoch == current else { return }
            self.loadCards()
        }
    }

    /// Sends a host slot answer. The pending link leaves the sheet at once; the browser opens only when the runtime answers
    /// `opened`. An approval decision counts as made only when the runtime accepts it; a refused one shows the failure and
    /// leaves the buttons for another try. Nothing is retried automatically.
    private func sendAnswer(_ ref: String, _ answer: CardAnswer) {
        guard let message = cardKey(ref) else { return }
        state.cards[message]?.pending = nil
        cardEventsInFlight[ref, default: 0] += 1
        state.cards[message]?.sending = true
        state.cards[message]?.failure = nil
        let current = epoch
        Task { [weak self, cards, account] in
            let result = await cards.answer(account: account, surfaceRef: ref, token: answer.token, slotID: answer.slotID, requestID: answer.requestID, outcome: answer.outcome)
            guard let self else { return }
            self.endCardEvent(ref)
            guard self.epoch == current else { return }
            if case .success(let step) = result, step.slotResult == "opened", let link = answer.link { CardLinkOpener.open(link) }
            if case .success(let step) = result, step.slotResult == "approval_decision" {
                self.state.cards[message]?.decided.insert(answer.requestID)
                // Confirm and deny carry the task.resolve body; cancel and unavailable carry none and only close the sheet.
                if case .approvalDecision(let outcome, let requestRef, _, let resolve?)? = step.hostRequest {
                    self.finishApproval(message, outcome: outcome, requestRef: requestRef, resolve: resolve)
                }
            }
            self.finishCardStep(message, ref: ref, result)
        }
    }

    /// The decision the runtime accepted is finished through the SDK: `grant.approve` or `grant.deny`, then `task.resolve` with
    /// the runtime's body unchanged. The card keeps "Waiting for confirmation" until the signed update or the task change. A
    /// refusal shows one line ("This request changed. Review it again.") and the cards are read again; nothing is retried.
    private func finishApproval(_ message: String, outcome: String, requestRef: String, resolve: JSONValue) {
        let current = epoch
        Task { [weak self, cards, account] in
            let result = await cards.finishApproval(account: account, outcome: outcome, requestRef: requestRef, taskResolve: resolve)
            guard let self, self.epoch == current else { return }
            if case .failure(let error) = result {
                self.state.cards[message]?.failure = error
                self.loadCards()
            }
        }
    }

    private func finishCardStep(_ message: String, ref: String, _ result: RepositoryResult<CardStep>) {
        state.cards[message]?.sending = (cardEventsInFlight[ref] ?? 0) > 0
        switch result {
        case .success(let step):
            state.cards[message]?.display = step.display
            // A link the author asked to open waits for the user's answer in the link sheet.
            if case .openURL? = step.hostRequest { state.cards[message]?.pending = step.hostRequest }
        case .failure(let error):
            state.cards[message]?.failure = error
        }
    }
}
