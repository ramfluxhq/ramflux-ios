// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import SwiftUI
import AppData
import RFDesign
import RFLocalization
public struct TasksScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: TasksState
    public let onAction: (TasksAction) -> Void
    public init(state: TasksState, onAction: @escaping (TasksAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureTasksStrings.text("tasks." + key, locale: locale) }
    private func status(_ value: String) -> String { copy(["proposed", "running", "needs_me", "done", "failed", "cancelled"].contains(value) ? value : "unknown") }
    public var body: some View {
        Group {
            if case .detail = state.mode, let row = state.selected { TasksDetailScreen(state: state, row: row, onAction: onAction) }
            else { regularBody }
        }.privacySensitive().rfHidesNavigationBar()
        .sheet(item: Binding(get: { state.approvalConfirmation }, set: { if $0 == nil { onAction(.cancelConfirmation) } })) { confirmation in
            RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                Text(copy(confirmation.approve ? "approval.approve.title" : "approval.deny.title")).rfFont(.page)
                TaskPermissionDetails(row: .approval(confirmation.approval))
                RFHostConfirmationActions(summary: FeatureTasksStrings.sentence(confirmation.approve ? "tasks.approval.approve.summary" : "tasks.approval.deny.summary", [.untrusted(confirmation.approval.tool), .untrusted(confirmation.approval.server)], locale: locale),
                    enabled: state.fresh && !state.busy, cancelEnabled: !state.busy, grantsAuthority: true, confirm: { onAction(.confirmApproval(confirmation.id)) }, cancel: { onAction(.cancelConfirmation) }).id(confirmation.id)
            }.padding(theme.gap) } }.interactiveDismissDisabled(state.busy)
        }
        .sheet(item: Binding(get: { state.confirmation }, set: { if $0 == nil { onAction(.cancelConfirmation) } })) { confirmation in
            RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                Text(copy("review")).rfFont(.page); facts(confirmation.attempt)
                RFHostConfirmationActions(summary: FeatureTasksStrings.sentence("tasks.confirm.summary", [.localized(copy(confirmation.attempt.arguments.kind.rawValue)), .untrusted(confirmation.attempt.arguments.task.title), .identifier(confirmation.attempt.arguments.task.id)], locale: locale), enabled: state.fresh && !state.busy && state.pending == nil, cancelEnabled: !state.busy, confirm: { onAction(.confirm(confirmation.id)) }, cancel: { onAction(.cancelConfirmation) }).id(confirmation.id)
            }.padding(theme.gap) } }.interactiveDismissDisabled(state.busy)
        }
    }
    private var regularBody: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(copy("title"), onBack: { dismiss() }, actionLabel: copy("refresh"), onAction: { onAction(.refresh) }, tag: "tasks-header")
            if state.loading || state.busy { ProgressView(copy("loading")) }
            if !state.fresh { Text(copy("stale")).rfFont(.caption) }
            if let pending = state.pending { Text(copy("pending")); facts(pending); Button(copy("reconcile")) { onAction(.reconcile(pending.operationID)) }.disabled(state.busy) }
            if let outcome = state.outcome { Text(copy(outcome.pending ? "waiting" : "submitted")) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            Button(copy("conversations")) { onAction(.mode(.conversations)) }
            Button(copy("permissions")) { onAction(.mode(.permissions)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .conversations:
            Text(copy("context"))
            LazyVStack(alignment: .leading, spacing: theme.gap / 2) {
                ForEach(state.conversations.rows) { row in KitRow(RFUntrustedText.clean(row.title), action: { onAction(.mode(.list(row.id))) }, icon: "messages-square", tag: "tasks-conversation-" + row.id)
                    .onAppear { if row.id == state.conversations.rows.last?.id, state.conversations.canLoadAfter { onAction(.loadMore) } } }
            }
            Button(copy("create")) { onAction(.unavailable) }
        case .list(let conversation):
            Text(conversation).rfFont(.caption)
            if state.tasks.isEmpty && !state.loading && state.failure == nil { Text(copy("empty")) }
            LazyVStack(alignment: .leading, spacing: theme.gap / 2) {
                ForEach(state.tasks.rows) { row in KitRow(RFUntrustedText.clean(row.title), action: { onAction(.mode(.detail(conversation: row.conversationID, task: row.id))) }, icon: "list-checks", value: status(row.status), tag: row.id)
                    .onAppear { if row.id == state.tasks.rows.last?.id, state.tasks.canLoadAfter { onAction(.loadMore) } } }
            }
        case .detail: EmptyView()
        case .permissions:
            Text(copy("noAuthority")).rfFont(.caption)
            if state.permissions.isEmpty && !state.loading && state.failure == nil { Text(copy("empty")) }
            LazyVStack(alignment: .leading, spacing: theme.gap / 2) {
            ForEach(state.permissions.rows) { row in Button { onAction(.mode(.permission(row.id))) } label: {
                VStack(alignment: .leading) {
                    switch row {
                    case .grant(let grant): Text(grant.state.tool); Text(copy("grant")); Text(grant.state.server).rfFont(.caption)
                    case .approval(let approval): Text(approval.tool); Text(copy("approval")); Text(approval.server).rfFont(.caption)
                    case .receipt(let receipt): Text(copy("receipt")); Text(receipt.binding.taskID).rfFont(.caption)
                    }
                }
            }.onAppear { if row.id == state.permissions.rows.last?.id, state.permissions.canLoadAfter { onAction(.loadMore) } } }
            }
        case .permission:
            if let row = state.selectedPermission {
                if case .approval(let approval) = row, approval.status == "pending" {
                    KitApprovalCard(requester: RFUntrustedText.clean(approval.server), status: copy("approval"), title: RFUntrustedText.clean(approval.tool),
                                    scopeLabel: copy("approval.scope"), scopeDetail: RFUntrustedText.clean(approval.scope ?? approval.capability),
                                    decline: copy("approval.deny"), approve: copy("approval.approve"),
                                    onDecline: { onAction(.prepareApproval(approve: false)) }, onApprove: { onAction(.prepareApproval(approve: true)) },
                                    actions: state.fresh && !state.busy, tag: "tasks-approval-card")
                    if approval.needsAppSignature { Text(copy("approval.appSignature")).rfFont(.caption).foregroundStyle(theme.secondary) }
                }
                TaskPermissionDetails(row: row)
            }
        }
    }
    private func facts(_ attempt: PendingTaskMutation) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            LabeledContent(copy("account"), value: state.accountID)
            LabeledContent(copy("conversation"), value: attempt.arguments.task.conversationID)
            LabeledContent(copy("task"), value: attempt.arguments.task.id)
            Text(untrusted: attempt.arguments.task.title)
            LabeledContent(copy("version"), value: attempt.arguments.task.version.formatted(.number.locale(locale)))
            Text(copy(attempt.arguments.kind.rawValue)).rfFont(.body, weight: .semibold)
        }
    }
}
