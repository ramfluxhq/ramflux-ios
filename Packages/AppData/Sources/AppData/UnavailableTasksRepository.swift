// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct UnavailableTasksRepository: TasksRepository {
    public init() {}
    public func page(account: String, conversation: String, cursor: String?) async -> RepositoryResult<TaskPage> { .failure(.sdkUnavailable) }
    public func detail(account: String, conversation: String, task: String) async -> RepositoryResult<TaskRecord> { .failure(.sdkUnavailable) }
    public func pending(account: String) async -> PendingTaskMutation? { nil }
    public func mutate(account: String, attempt: PendingTaskMutation) async -> RepositoryResult<TaskMutationOutcome> { .failure(.sdkUnavailable) }
    public func permissions(account: String) async -> RepositoryResult<[PermissionRecord]> { .failure(.sdkUnavailable) }
    public func unavailable() -> AppFailure { .unavailableResource("tasks.unavailable") }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}
