// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public struct UnavailableCallsRepository: CallsRepository {
    public init() {}
    public func list(account: String) async -> RepositoryResult<[CallRecord]> { .failure(.sdkUnavailable) }
    public func pending(account: String) async -> CallSignalAttempt? { nil }
    public func signal(account: String, attempt: CallSignalAttempt) async -> RepositoryResult<CallRecord> { .failure(.sdkUnavailable) }
    public func start(account: String, conversation: String) async -> RepositoryResult<CallRecord> { .failure(audioUnavailable()) }
    public func answer(account: String, expected: CallRecord) async -> RepositoryResult<CallRecord> { .failure(audioUnavailable()) }
    public func audioUnavailable() -> AppFailure { .notAvailable(AppDataStrings.text("calls.audioUnavailable")) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}
