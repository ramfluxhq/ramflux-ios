// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Cards through the SDK: `surface.list` for the cards of a conversation and the `card.session.*` calls of the
/// per-account pool for everything drawn or acted on.
public struct NativeCardsRepository: CardsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    private let registry: CardSessionRegistry

    public init(client: RamfluxClient, updates: NativeUpdateSource, registry: CardSessionRegistry? = nil) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates
        self.registry = registry ?? CardSessionRegistry(client: client)
    }

    public func surfaces(account: String, conversation: String, cursor: String?) async -> RepositoryResult<CardSurfacePage> {
        guard !conversation.isEmpty, conversation.utf8.count <= 256 else { return .failure(.invalidInput) }
        do {
            var body: [String: JSONValue] = ["conversation_id": .string(conversation), "limit": .number(20)]
            if let cursor { body["cursor"] = .string(cursor) }
            let page = try await gateway.call(.surfaceList, account: account, body: .object(body))
            var cards: [CardSurface] = []
            for row in try ProxyGateway.rows(page, "surfaces") where row["removed"] != .bool(true) {
                guard let ref = row["surface_ref"]?.string, !ref.isEmpty, ref.utf8.count <= 512 else { throw AppFailure.invalidData }
                cards.append(CardSurface(surfaceRef: ref, conversationID: row["conversation_id"]?.string ?? conversation, messageID: row["message_id"]?.string,
                                         authorPrincipalID: row["author_principal_id"]?.string, version: CardJSON.uint(row["version"]) ?? 0,
                                         closed: row["closed"] == .bool(true), outOfSync: row["out_of_sync"] == .bool(true)))
            }
            let next = page["next_cursor"]?.string.flatMap { $0.isEmpty || $0 == cursor ? nil : $0 }
            return .success(CardSurfacePage(surfaces: cards, nextCursor: next))
        } catch { return .failure(Self.failure(error)) }
    }

    public func open(account: String, surface: CardSurface, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay> {
        await run(account) { try await $0.open(surfaceRef: surface.surfaceRef, locale: locale, dark: dark) }
    }

    public func refresh(account: String, surface: CardSurface, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay> {
        await run(account) { try await $0.refresh(surfaceRef: surface.surfaceRef, version: surface.version, locale: locale, dark: dark) }
    }

    public func resume(account: String, surfaceRef: String) async -> RepositoryResult<CardDisplay> {
        await run(account) { try await $0.resume(surfaceRef: surfaceRef) }
    }

    public func present(account: String, surfaceRef: String, locale: String, dark: Bool) async -> RepositoryResult<CardDisplay> {
        await run(account) { try await $0.present(surfaceRef: surfaceRef, locale: locale, dark: dark) }
    }

    public func event(account: String, surfaceRef: String, key: String, event: CardHostEvent) async -> RepositoryResult<CardStep> {
        await run(account) { try await $0.event(surfaceRef: surfaceRef, key: key, event: event) }
    }

    public func answer(account: String, surfaceRef: String, token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome) async -> RepositoryResult<CardStep> {
        await run(account) { try await $0.answer(surfaceRef: surfaceRef, token: token, slotID: slotID, requestID: requestID, outcome: outcome) }
    }

    public func requestResync(account: String, surfaceRef: String) async -> RepositoryResult<Void> {
        guard !surfaceRef.isEmpty, surfaceRef.utf8.count <= 512 else { return .failure(.invalidInput) }
        do {
            _ = try await gateway.call(.surfaceRequestResync, account: account, body: .object(["surface_ref": .string(surfaceRef)]))
            return .success(())
        } catch { return .failure(Self.failure(error)) }
    }

    public func retain(account: String, surfaceRefs: Set<String>) async {
        await registry.pool(account: account).retain(surfaceRefs: surfaceRefs)
    }

    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }

    private func run<Value: Sendable>(_ account: String, _ work: (CardSessionPool) async throws -> Value) async -> RepositoryResult<Value> {
        do { return .success(try await work(await registry.pool(account: account))) } catch { return .failure(Self.failure(error)) }
    }

    /// A card session refusal keeps its runtime name so the timeline can say what happened; other errors map as usual.
    static func failure(_ error: any Error) -> AppFailure {
        if let refusal = CardSessionRefusal.of(error) { return .typedRefusal(refusal.rawValue) }
        if error is CardTreeError { return .invalidData }
        return AppFailure.map(error)
    }
}
