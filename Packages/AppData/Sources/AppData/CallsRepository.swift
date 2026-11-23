// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// One page of call history, newest first. `call.list` is unpaged today (at most 128 rows), so
/// the first page has no cursor; callers still follow `nextCursor` until it is nil.
public struct CallHistoryPage: Equatable, Sendable {
    public let rows: [CallRecord]
    public let nextCursor: String?
    public init(rows: [CallRecord], nextCursor: String?) { self.rows = rows; self.nextCursor = nextCursor }
}

/// One-to-one calls through `call.*`, live state through the `call.changed` topic, and the media
/// engine boundary. Invite and answer are sent only while the engine is available.
public protocol CallsRepository: Sendable {
    func history(account: String, cursor: String?) async -> RepositoryResult<CallHistoryPage>
    func pending(account: String) async -> CallSignalAttempt?
    /// Decline, hang up or answer the exact call version the user saw. An uncertain attempt
    /// stays pending and may only be retried with its original operation id.
    func signal(account: String, attempt: CallSignalAttempt) async -> RepositoryResult<CallRecord>
    /// `call.invite` for a direct conversation (voice only in the SDK today).
    func start(account: String, conversation: String) async -> RepositoryResult<CallRecord>
    /// Reads `call.media.session` once for an active call and hands it to the engine. A second
    /// request for the same call succeeds without reading again.
    func connectMedia(account: String, call: CallRecord) async -> RepositoryResult<Void>
    func control(_ control: CallMediaControl, callID: String) async -> RepositoryResult<Void>
    func stopMedia(callID: String) async
    /// The system activated or deactivated the call audio session.
    func audioSession(active: Bool) async
    func mediaEvents() -> AsyncStream<CallMediaEvent>
    @MainActor func attachVideo(_ surface: (any CallVideoSurface)?, slot: CallVideoSlot, callID: String)
    func observe(account: String) async -> RepositoryObservation
    func mediaAvailability() -> CallMediaAvailability
}

public extension CallsRepository {
    func audioUnavailable() -> AppFailure { mediaAvailability().failure ?? .unavailableResource("calls.audioUnavailable") }
    func connectMedia(account: String, call: CallRecord) async -> RepositoryResult<Void> { .failure(audioUnavailable()) }
    func control(_ control: CallMediaControl, callID: String) async -> RepositoryResult<Void> { .failure(audioUnavailable()) }
    func stopMedia(callID: String) async {}
    func audioSession(active: Bool) async {}
    func mediaEvents() -> AsyncStream<CallMediaEvent> { AsyncStream { $0.finish() } }
    @MainActor func attachVideo(_ surface: (any CallVideoSurface)?, slot: CallVideoSlot, callID: String) {}
    func mediaAvailability() -> CallMediaAvailability { RefusingCallMediaEngine().availability() }
}
