// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public protocol TasksRepository: Sendable {
    func page(account: String, conversation: String, cursor: String?) async -> RepositoryResult<TaskPage>
    func detail(account: String, conversation: String, task: String) async -> RepositoryResult<TaskRecord>
    func pending(account: String) async -> PendingTaskMutation?
    func mutate(account: String, attempt: PendingTaskMutation) async -> RepositoryResult<TaskMutationOutcome>
    func permissions(account: String) async -> RepositoryResult<[PermissionRecord]>
    func unavailable() -> AppFailure
    func observe(account: String) async -> RepositoryObservation
}
