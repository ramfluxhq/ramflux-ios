// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// Sole owner of the application session. Transport and secret types stay inside AppData.
/// One subscriber per app scene; closing the scene ends observation and suspends storage.
public protocol SessionRepository: Sendable {
    func snapshots() async -> AsyncStream<SessionSnapshot>
    func activate() async -> RepositoryResult<SessionSnapshot>
    func suspend() async -> RepositoryResult<Void>
    func selectAccount(_ id: String) async -> RepositoryResult<SessionSnapshot>
}
