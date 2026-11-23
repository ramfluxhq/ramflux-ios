// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// One page of a conversation's surfaces, newest first.
public struct SurfacePage: Equatable, Sendable {
    public let surfaces: [SurfaceRecord]
    public let nextCursor: String?
    public init(surfaces: [SurfaceRecord], nextCursor: String?) { self.surfaces = surfaces; self.nextCursor = nextCursor }
}

/// The outcome of a surface action as the daemon reports it.
public struct SurfaceActionOutcome: Equatable, Sendable {
    public let accepted: Bool
    public let queued: Bool
    /// The refusal code of a non-accepted action (for example `stale_version`, `closed`).
    public let reasonCode: String?
    public init(accepted: Bool, queued: Bool, reasonCode: String?) { self.accepted = accepted; self.queued = queued; self.reasonCode = reasonCode }
}

/// Agent surfaces (cards) in conversations: `surface.list` and `surface.get` to read, and
/// `surface.action` to act on a shown surface, bound to its version and hash.
public protocol CardsRepository: Sendable {
    func surfaces(account: String, conversation: String, cursor: String?) async -> RepositoryResult<SurfacePage>
    func surface(account: String, surfaceRef: String) async -> RepositoryResult<SurfaceRecord?>
    /// Sends the button's event. The surface is read again first; a changed version or hash
    /// refuses with `stale_version` without sending. `messageID` is kept by the caller and reused
    /// on retries so the daemon can recognise a replay.
    func act(account: String, shown: SurfaceRecord, buttonID: String, drafts: [String: SurfaceInput], messageID: String) async -> RepositoryResult<SurfaceActionOutcome>
    func observe(account: String) async -> RepositoryObservation
}

public extension CardsRepository {
    func surfaces(account: String, conversation: String, cursor: String?) async -> RepositoryResult<SurfacePage> { .failure(.unavailableResource("cards.unavailable")) }
    func surface(account: String, surfaceRef: String) async -> RepositoryResult<SurfaceRecord?> { .failure(.unavailableResource("cards.unavailable")) }
    func act(account: String, shown: SurfaceRecord, buttonID: String, drafts: [String: SurfaceInput], messageID: String) async -> RepositoryResult<SurfaceActionOutcome> { .failure(.unavailableResource("cards.unavailable")) }
    func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .unavailableResource("cards.unavailable")) }
    /// A fresh action message id: 128 random bits, base64url.
    static func newActionMessageID() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return CanonicalJSON.base64URL(Data(bytes))
    }
}
