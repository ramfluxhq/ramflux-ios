// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct UnavailableSessionRepository: SessionRepository {
    public let reason: UnavailableReason
    public init(reason: UnavailableReason = .nativeCoreMissing) { self.reason = reason }
    public func snapshots() async -> AsyncStream<SessionSnapshot> {
        AsyncStream { continuation in continuation.yield(SessionSnapshot(phase: .unavailable(reason))); continuation.finish() }
    }
    public func activate() async -> RepositoryResult<SessionSnapshot> { .success(SessionSnapshot(phase: .unavailable(reason))) }
    public func suspend() async -> RepositoryResult<Void> { .success(()) }
    public func selectAccount(_ id: String) async -> RepositoryResult<SessionSnapshot> { .failure(.notAvailable(reason.message)) }
}
