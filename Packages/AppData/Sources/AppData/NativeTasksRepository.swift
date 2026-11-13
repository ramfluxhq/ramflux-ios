// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RamfluxCore
public struct NativeTasksRepository: TasksRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    private let journal = RetainedMutation<TaskMutationArguments, TaskMutationOutcome>()
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func page(account: String, conversation: String, cursor: String?) async -> RepositoryResult<TaskPage> {
        do {
            guard !conversation.isEmpty else { throw AppFailure.invalidInput }
            let body = try await gateway.call(.taskList, account: account, body: .object(["conversation_id": .string(conversation), "limit": .number(50), "cursor": .string(cursor ?? "")]))
            let rows = try ProxyGateway.rows(body, "tasks").map(Self.record)
            guard rows.allSatisfy({ $0.conversationID == conversation }), Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }
            return .success(TaskPage(rows: rows, nextCursor: body["next_cursor"]?.string))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func detail(account: String, conversation: String, task: String) async -> RepositoryResult<TaskRecord> {
        do {
            let row = try Self.record(await gateway.call(.taskGet, account: account, body: .object(["conversation_id": .string(conversation), "task_id": .string(task)])))
            guard row.id == task, row.conversationID == conversation else { throw AppFailure.invalidData }; return .success(row)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func pending(account: String) async -> PendingTaskMutation? {
        guard let entry = await journal.snapshot(scope: account), entry.unresolved else { return nil }; return PendingTaskMutation(arguments: entry.arguments, operationID: entry.operationID)
    }
    public func mutate(account: String, attempt: PendingTaskMutation) async -> RepositoryResult<TaskMutationOutcome> {
        await journal.run(scope: account, arguments: attempt.arguments, operationID: attempt.operationID) {
            let selected = attempt.arguments.task, kind = attempt.arguments.kind
            switch await detail(account: account, conversation: selected.conversationID, task: selected.id) { case .success(let current): guard current == selected else { return .failure(.busy) }; case .failure(let failure): return .failure(failure) }
            guard !selected.pendingResolution, kind == .cancel ? ["running", "needs_me", "proposed"].contains(selected.status) : selected.status == "proposed" else { return .failure(.invalidInput) }
            var body: [String: JSONValue] = ["conversation_id": .string(selected.conversationID), "task_id": .string(selected.id), "message_id": .string(attempt.operationID)]
            if kind == .cancel { body["base_revision"] = .unsigned(selected.version) }
            else { let (next, overflow) = selected.version.addingReportingOverflow(1); guard !overflow else { return .failure(.invalidInput) }; body["version"] = .unsigned(next) }
            let response: JSONValue
            do { response = try await gateway.call(kind == .accept ? .taskAccept : kind == .decline ? .taskDecline : .taskCancel, account: account, body: .object(body), operationID: attempt.operationID) }
            catch { return .failure(AppFailure.map(error)) }
            guard response["task_id"] == .string(selected.id), case .bool(let accepted) = response["accepted"], case .bool(let pending) = response["pending"] else { return .failure(.outcomeUnknown) }
            guard accepted || pending else { return .failure(.invalidData) }
            return .success(TaskMutationOutcome(taskID: selected.id, pending: pending))
        }
    }
    public func permissions(account: String) async -> RepositoryResult<[PermissionRecord]> {
        do {
            let body = try await gateway.call(.grantList, account: account)
            let rows = try ProxyGateway.rows(body, "grants").map(PermissionProjection.grant) + ProxyGateway.rows(body, "approvals").map(PermissionProjection.approval)
            guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }; return .success(rows)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func unavailable() -> AppFailure { .unavailableResource("tasks.unavailable") }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    private static func record(_ row: JSONValue) throws -> TaskRecord {
        let version: UInt64?
        switch row["version"] { case .unsigned(let value): version = value; case .number(let value): version = UInt64(exactly: value); default: version = nil }
        guard let version else { throw AppFailure.invalidData }
        let steps = try ProxyGateway.rows(row, "steps").map { step in TaskStepRecord(id: try ProxyGateway.text(step, "id"), title: try ProxyGateway.text(step, "title"), status: try ProxyGateway.text(step, "state"), interventionKind: step["needs_me"]?["kind"]?.string) }
        return TaskRecord(id: try ProxyGateway.text(row, "task_id"), conversationID: try ProxyGateway.text(row, "conversation_id"), version: version, title: try ProxyGateway.text(row, "title"), status: try ProxyGateway.text(row, "state"), requester: row["requester"]?.string, assignee: try ProxyGateway.text(row, "assignee"), steps: steps, result: row["result_summary"]?.string, pendingResolution: row["pending_resolution"] != nil && row["pending_resolution"] != .null, stalled: row["stalled_by_assignee"] == .bool(true))
    }
}
