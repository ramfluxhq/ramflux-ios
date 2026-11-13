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
    @Test func structuredGrantAndMixedPendingDecisionReceiptsPreserveTheirDistinctFacts() async {
        let fixture = ProxyTransport { request in
            #expect(request.method == "grant.list")
            let state: JSONValue = .object(["server_id": .string("service"), "tool_name": .string("email"), "tool_scope": .string("outbox"), "registry_hash": .string("registry"), "tool_manifest_set_hash": .string("manifest"), "full_delegation": .bool(false), "allowed_capabilities": .array([.string("email_send")]), "revoked": .bool(true), "expires_at": .number(1_900_000_000)])
            let signing: JSONValue = .object(["approval_id": .string("same"), "grant_id": .string("same"), "server_id": .string("service"), "tool_name": .string("email"), "tool_scope": .string("outbox"), "capability": .string("email_send"), "registry_hash": .string("registry"), "tool_manifest_set_hash": .string("manifest"), "full_delegation": .bool(false), "single_use": .bool(true), "arguments_hash": .string("hash"), "expires_at": .number(1_900_000_000)])
            let grant: JSONValue = .object(["grant_id": .string("same"), "state": state, "signed_by_device_id": .string("phone"), "signer_public_key": .string("key"), "signature": .string("signature"), "signing_body": signing, "confirmation_mode": .string("explicit")])
            let pending: JSONValue = .object(["approval_id": .string("same"), "server_id": .string("service"), "tool_name": .string("email"), "capability": .string("email_send"), "risk_level": .string("high"), "tool_scope": .string("outbox"), "confirmation_mode": .string("explicit"), "expires_at": .number(1_900_000_000), "status": .string("pending"), "details": .object(["arguments_hash": .string("bound-hash")])])
            let binding: JSONValue = .object(["conversation_id": .string("thread"), "task_id": .string("t"), "step_id": .string("step"), "opening_revision": .unsigned(UInt64.max), "requester": .string("requester"), "assignee": .string("agent"), "executor_device_id": .string("executor")])
            let receipt: JSONValue = .object(["approval_id": .string("task_approval_request"), "decision_id": .string("decision"), "grant_id": .string("grant"), "task_binding": binding, "status": .string("denied"), "delivery_state": .string("failed"), "reason_code": .string("retry_exhausted"), "expires_at": .number(1_900_000_001)])
            return .object(["grants": .array([grant]), "approvals": .array([pending, receipt])])
        }
        guard case .success(let rows) = await repository(fixture).permissions(account: "a") else { Issue.record("Valid mixed SDK permission page was refused"); return }
        #expect(rows.count == 3); #expect(Set(rows.map(\.id)).count == 3)
        guard case .grant(let grant)? = rows.first, case .approval(let approval)? = rows.dropFirst().first, case .receipt(let receipt)? = rows.last else { Issue.record("Permission variants were conflated"); return }
        #expect(grant.referenceID == "same"); #expect(grant.state.revoked); #expect(grant.state.allowedCapabilities == ["email_send"]); #expect(grant.state.expiresAt == 1_900_000_000); #expect(grant.argumentsHash == "hash")
        #expect(approval.status == "pending"); #expect(approval.argumentsHash == "bound-hash")
        #expect(receipt.referenceID == "task_approval_request"); #expect(receipt.decisionID == "decision"); #expect(receipt.grantID == "grant"); #expect(receipt.status == "denied"); #expect(receipt.deliveryState == "failed"); #expect(receipt.reasonCode == "retry_exhausted"); #expect(receipt.binding.openingRevision == UInt64.max); #expect(receipt.expiresAt == 1_900_000_001)
        #expect(fixture.calls.withLock { $0.count == 1 })
    }
}
