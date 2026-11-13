// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// Availability only. Signed native runtime/session integration is deferred by the owner.
public protocol CardsRepository: Sendable { func availability() async -> RepositoryResult<Void> }
