// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum ContactMutationArguments: Equatable, Sendable {
    case add(String), decide(String, ContactDecision)
    /// A change to an accepted contact: its principal id and the change.
    case change(String, ContactChange)
}
