// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct UnavailableCardsRepository: CardsRepository {
    public init() {}
    public func availability() async -> RepositoryResult<Void> { .failure(.unavailableResource("cards.unavailable")) }
}
