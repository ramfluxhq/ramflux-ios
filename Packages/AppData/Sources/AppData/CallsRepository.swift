// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public protocol CallsRepository: Sendable {
    func list(account: String) async -> RepositoryResult<[CallRecord]>
    func pending(account: String) async -> CallSignalAttempt?
    func signal(account: String, attempt: CallSignalAttempt) async -> RepositoryResult<CallRecord>
    func start(account: String, conversation: String) async -> RepositoryResult<CallRecord>
    func answer(account: String, expected: CallRecord) async -> RepositoryResult<CallRecord>
    func observe(account: String) async -> RepositoryObservation
    func audioUnavailable() -> AppFailure
}
