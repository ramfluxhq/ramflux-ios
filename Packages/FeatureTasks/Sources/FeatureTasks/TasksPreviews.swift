// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum TasksPreviews {
    public static var states: [TasksState] {
        let modes: [TasksMode] = [.conversations, .list("preview-thread"), .detail(conversation: "preview-thread", task: "preview-task"), .permissions, .permission("approval:preview-approval")]
        let permission = PermissionRecord.approval(PermissionApproval(referenceID: "preview-approval", server: "preview-service", tool: "preview-tool", capability: "email_send", status: "pending", expiresAt: 4_102_444_800, argumentsHash: "preview-arguments-hash"))
        let rows: [TaskRecord] = ["proposed", "running", "needs_me", "done", "failed", "cancelled"].enumerated().map { index, status -> TaskRecord in TaskRecord(id: "preview-task-\(index)", conversationID: "preview-thread", version: 7, title: "Research", status: status, requester: "preview-account", assignee: "preview-agent", steps: [TaskStepRecord(id: "preview-step", title: "Review sources", status: status, interventionKind: status == "needs_me" ? "approval" : nil)], result: status == "done" ? "Review completed" : nil) }
        var values = modes.map { mode in
            var state = TasksState(mode: mode); state.accountID = "preview-account"; state.conversations = [ConversationRecord(id: "preview-thread", title: "Research", preview: "")]; state.rows = rows; state.selected = rows[0]; state.permissions = [permission]; state.selectedPermission = permission; state.fresh = true; return state
        }
        values += rows.map { row in var state = TasksState(mode: .detail(conversation: row.conversationID, task: row.id)); state.selected = row; state.fresh = true; return state }
        let grantState = PermissionGrantState(server: "preview-service", tool: "preview-tool", registryHash: "preview-registry", manifestHash: "preview-manifest", fullDelegation: false, allowedCapabilities: ["email_send"], revoked: true, expiresAt: 4_102_444_800)
        let binding = PermissionTaskBinding(conversationID: "preview-thread", taskID: "preview-task", stepID: "preview-step", openingRevision: 7, requester: "preview-requester", assignee: "preview-agent", executorDeviceID: "preview-executor")
        let variants: [PermissionRecord] = [permission, .grant(PermissionGrant(referenceID: "preview-grant", state: grantState)), .receipt(PermissionReceipt(referenceID: "preview-receipt", decisionID: "preview-decision", grantID: "preview-grant", binding: binding, status: "denied", deliveryState: "failed", reasonCode: "retry_exhausted", expiresAt: 4_102_444_800))]
        values += variants.map { record in var state = TasksState(mode: .permission(record.id)); state.permissions = variants; state.selectedPermission = record; state.fresh = true; return state }
        var loading = TasksState(); loading.loading = true; var offline = TasksState(); offline.failure = .offline
        var unknown = values[2]; unknown.pending = PendingTaskMutation(arguments: TaskMutationArguments(task: rows[0], kind: .accept), operationID: "preview-original-key"); unknown.fresh = false
        return values + [loading, offline, unknown]
    }
}
#Preview("Tasks") { RFThemeScope { TasksScreen(state: TasksPreviews.states[1], onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(TasksPreviews.states.indices, id: \.self) { index in TasksScreen(state: TasksPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(TasksPreviews.states.indices, id: \.self) { index in TasksScreen(state: TasksPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
