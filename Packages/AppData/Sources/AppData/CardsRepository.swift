// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// One card of a conversation as `surface.list` reports it: metadata only. Content comes from a card session.
public struct CardSurface: Equatable, Identifiable, Sendable {
    public var id: String { surfaceRef }
    public let surfaceRef: String
    public let conversationID: String
    /// The message that carried the card; the timeline draws the card under it.
    public let messageID: String?
    public let authorPrincipalID: String?
    /// The published surface version the list shows.
    public let version: UInt64
    public let closed: Bool
    public let outOfSync: Bool

    public init(surfaceRef: String, conversationID: String, messageID: String?, authorPrincipalID: String?, version: UInt64, closed: Bool, outOfSync: Bool) {
        self.surfaceRef = surfaceRef; self.conversationID = conversationID; self.messageID = messageID; self.authorPrincipalID = authorPrincipalID
        self.version = version; self.closed = closed; self.outOfSync = outOfSync
    }
}

/// One page of a conversation's cards, newest first.
public struct CardSurfacePage: Equatable, Sendable {
    public let surfaces: [CardSurface]
    public let nextCursor: String?
    public init(surfaces: [CardSurface], nextCursor: String?) { self.surfaces = surfaces; self.nextCursor = nextCursor }
}

/// Agent cards in conversations. The list comes from `surface.list`; every card is drawn from its runtime session
/// (`card.session.*`), which owns the signed content, the authority and the drafts. Nothing here parses card content.
public protocol CardsRepository: Sendable {
    func surfaces(account: String, conversation: String, cursor: String?) async -> RepositoryResult<CardSurfacePage>
    /// Opens the card's session, or returns the open one. `dark` and `locale` are the presentation of the open.
    func open(account: String, surface: CardSurface, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay>
    /// Brings the session to the surface version the list shows (an update when it moved).
    func refresh(account: String, surface: CardSurface, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay>
    /// The first tap on a suspended card: resumes its session with fresh tokens.
    func resume(account: String, surfaceRef: String) async -> RepositoryResult<CardDisplay>
    func present(account: String, surfaceRef: String, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay>
    /// A host event on a node of the held tree. A submit that the event starts is sent in the same step.
    func event(account: String, surfaceRef: String, key: String, event: CardHostEvent) async -> RepositoryResult<CardStep>
    /// The host's answer to a host slot (a link the user confirmed or cancelled, an approval decision).
    func answer(account: String, surfaceRef: String, token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome) async -> RepositoryResult<CardStep>
    /// Asks the SDK to re-read the surface after an out-of-sync signal.
    func requestResync(account: String, surfaceRef: String) async -> RepositoryResult<Void>
    /// Finishes an approval decision the runtime accepted: `grant.approve` (confirm) or `grant.deny` (deny) with the request
    /// reference, then `task.resolve` with the runtime's body unchanged. Nothing is retried.
    func finishApproval(account: String, outcome: String, requestRef: String, taskResolve: JSONValue) async -> RepositoryResult<Void>
    /// The image of an Image host slot (`attachment` of the slot), read through the object API within the decoder limits.
    func image(account: String, surfaceRef: String, attachment: JSONValue?) async -> CardImageResult
    /// Disposes the sessions of cards that left the loaded window; the pool keeps at most 24 open.
    func retain(account: String, surfaceRefs: Set<String>) async
    func observe(account: String) async -> RepositoryObservation
}

public extension CardsRepository {
    private static var unavailable: AppFailure { .unavailableResource("cards.unavailable") }
    func surfaces(account: String, conversation: String, cursor: String?) async -> RepositoryResult<CardSurfacePage> { .failure(Self.unavailable) }
    func open(account: String, surface: CardSurface, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay> { .failure(Self.unavailable) }
    func refresh(account: String, surface: CardSurface, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay> { .failure(Self.unavailable) }
    func resume(account: String, surfaceRef: String) async -> RepositoryResult<CardDisplay> { .failure(Self.unavailable) }
    func present(account: String, surfaceRef: String, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay> { .failure(Self.unavailable) }
    func event(account: String, surfaceRef: String, key: String, event: CardHostEvent) async -> RepositoryResult<CardStep> { .failure(Self.unavailable) }
    func answer(account: String, surfaceRef: String, token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome) async -> RepositoryResult<CardStep> { .failure(Self.unavailable) }
    func requestResync(account: String, surfaceRef: String) async -> RepositoryResult<Void> { .failure(Self.unavailable) }
    func finishApproval(account: String, outcome: String, requestRef: String, taskResolve: JSONValue) async -> RepositoryResult<Void> { .failure(Self.unavailable) }
    func image(account: String, surfaceRef: String, attachment: JSONValue?) async -> CardImageResult { .unavailable }
    func retain(account: String, surfaceRefs: Set<String>) async {}
    func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: Self.unavailable) }
}
