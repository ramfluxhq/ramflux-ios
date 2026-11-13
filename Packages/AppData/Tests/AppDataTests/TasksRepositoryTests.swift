// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct TasksRepositoryTests {
    private func row(_ version: UInt64 = 1) -> JSONValue {
        .object(["task_id": .string("t"), "conversation_id": .string("thread"), "version": .unsigned(version), "title": .string("Review"), "state": .string("proposed"), "requester": .null, "assignee": .string("agent"), "steps": .array([.object(["id": .string("step"), "title": .string("Review sources"), "state": .string("proposed"), "needs_me": .null])]), "pending_resolution": .null])
    }
    private func repository(_ fixture: ProxyTransport) -> NativeTasksRepository { let client = RamfluxClient(transport: fixture); return NativeTasksRepository(client: client, updates: NativeUpdateSource(client: client)) }
    @Test func readsAreConversationScopedAndPreserveCursorAndExactRevision() async {
        let fixture = ProxyTransport { request in
            #expect(request.body["conversation_id"] == .string("thread")); #expect(request.body["limit"] == .number(50)); #expect(request.body["cursor"] == .string("task/view/next"))
            return .object(["tasks": .array([row(UInt64.max)]), "next_cursor": .string("task/view/later")])
        }
        guard case .success(let page) = await repository(fixture).page(account: "a", conversation: "thread", cursor: "task/view/next") else { Issue.record("Page failed"); return }
        #expect(page.rows.first?.version == UInt64.max); #expect(page.nextCursor == "task/view/later")
    }
    @Test func taskAcceptanceUsesNextVersionAndFrozenMessageKeyAndKeepsPendingDistinct() async {
        let fixture = ProxyTransport { request in
            if request.method == "task.get" { return row() }
            #expect(request.method == "task.accept"); #expect(request.body["version"] == .unsigned(2)); #expect(request.body["message_id"] == .string("original")); #expect(request.operationID?.rawValue == "original")
            return .object(["task_id": .string("t"), "accepted": .bool(false), "pending": .bool(true), "delivery_state": .string("submitted")])
        }
        let repo = repository(fixture)
        guard case .success(let task) = await repo.detail(account: "a", conversation: "thread", task: "t") else { Issue.record("Task absent"); return }
        #expect(await repo.mutate(account: "a", attempt: PendingTaskMutation(arguments: TaskMutationArguments(task: task, kind: .accept), operationID: "original")) == .success(TaskMutationOutcome(taskID: "t", pending: true)))
    }
    @Test func changedTaskAndOverflowRejectBeforeAuthoringAndMalformedAckRetainsKey() async {
        let fixture = ProxyTransport { request in request.method == "task.get" ? row() : .null }, repo = repository(ProxyTransport { _ in row(UInt64.max) })
        guard case .success(let task) = await repo.detail(account: "a", conversation: "thread", task: "t") else { Issue.record("No max revision"); return }
        #expect(await repo.mutate(account: "a", attempt: PendingTaskMutation(arguments: TaskMutationArguments(task: task, kind: .accept), operationID: "overflow")) == .failure(.invalidInput))
        let native = repository(fixture)
        #expect(await native.mutate(account: "a", attempt: PendingTaskMutation(arguments: TaskMutationArguments(task: task, kind: .cancel), operationID: "stale")) == .failure(.busy))
        guard case .success(let actual) = await native.detail(account: "a", conversation: "thread", task: "t") else { Issue.record("No current task"); return }
        let attempt = PendingTaskMutation(arguments: TaskMutationArguments(task: actual, kind: .decline), operationID: "unknown")
        #expect(await native.mutate(account: "a", attempt: attempt) == .failure(.outcomeUnknown)); #expect(await native.pending(account: "a") == attempt)
    }
    @Test func grantsUseSigningBodyAndApprovalAndGrantIdsCannotCollide() async {
        let fixture = ProxyTransport { request in
            #expect(request.method == "grant.list")
            let facts: [String: JSONValue] = ["server_id": .string("service"), "tool_name": .string("email"), "capability": .string("email_send"), "expires_at": .number(1_900_000_000), "arguments_hash": .string("hash")]
            var approval = facts; approval["approval_id"] = .string("same"); approval["status"] = .string("pending"); approval["details"] = .object(["arguments_hash": .string("bound-hash")])
            return .object(["grants": .array([.object(["grant_id": .string("same"), "state": .string("active"), "signing_body": .object(facts)])]), "approvals": .array([.object(approval)])])
        }
        guard case .success(let rows) = await repository(fixture).permissions(account: "a") else { Issue.record("Permission mapping failed"); return }
        #expect(rows.count == 2); #expect(Set(rows.map(\.id)).count == 2); #expect(rows.first?.argumentsHash == "hash"); #expect(rows.last?.argumentsHash == "bound-hash")
        #expect(fixture.calls.withLock { $0.count == 1 })
    }
}
