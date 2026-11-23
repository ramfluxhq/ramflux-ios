// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public protocol TasksRepository: Sendable {
    func page(account: String, conversation: String, cursor: String?) async -> RepositoryResult<TaskPage>
    func detail(account: String, conversation: String, task: String) async -> RepositoryResult<TaskRecord>
    func pending(account: String) async -> PendingTaskMutation?
    func mutate(account: String, attempt: PendingTaskMutation) async -> RepositoryResult<TaskMutationOutcome>
    func permissions(account: String) async -> RepositoryResult<[PermissionRecord]>
    /// The same records behind the paged row interface (`grant.list` is unpaged).
    func permissionsPage(account: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<PermissionRecord>>
    /// `grant.approve` / `grant.deny` for a pending approval, after re-reading it unchanged. Approving a
    /// `remote_app` approval needs an app-signed `mcp.approval.granted`, which this app cannot produce.
    func decideApproval(account: String, approval: PermissionApproval, approve: Bool, operationID: String) async -> RepositoryResult<Void>
    func unavailable() -> AppFailure
    func observe(account: String) async -> RepositoryObservation
}
