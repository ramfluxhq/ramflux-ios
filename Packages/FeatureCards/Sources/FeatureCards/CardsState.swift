// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct CardsState: Equatable, Sendable {
    public var checking = false
    /// True once the repository confirmed that cards render in conversations.
    public var available = false
    public var failure: AppFailure = .unavailableResource("cards.unavailable")
    public init() {}
}
