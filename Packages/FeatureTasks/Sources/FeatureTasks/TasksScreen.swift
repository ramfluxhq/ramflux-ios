// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import SwiftUI
import AppData
import RFDesign
public struct TasksScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: TasksState
    public let onAction: (TasksAction) -> Void
    public init(state: TasksState, onAction: @escaping (TasksAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureTasksStrings.text("tasks." + key, locale: locale) }
    private func status(_ value: String) -> String { copy(["proposed", "running", "needs_me", "done", "failed", "cancelled"].contains(value) ? value : "unknown") }
    public var body: some View {
        Group {
            if case .detail = state.mode, let row = state.selected { TasksDetailScreen(state: state, row: row, onAction: onAction) }
            else { regularBody }
        }.privacySensitive()
        .sheet(item: Binding(get: { state.confirmation }, set: { if $0 == nil { onAction(.cancelConfirmation) } })) { confirmation in
            RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                Text(copy("review")).font(theme.pageFont); facts(confirmation.attempt)
                RFHostHoldToConfirm(label: copy("confirm"), enabled: state.fresh && !state.busy && state.pending == nil) { onAction(.confirm(confirmation.id)) }.id(confirmation.id)
                Button(copy("dismiss")) { onAction(.cancelConfirmation) }.disabled(state.busy)
            }.padding(theme.gap) } }.interactiveDismissDisabled(state.busy)
        }
    }
    private var regularBody: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            RFPageHeader(title: copy("title"), subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { Button(copy("refresh")) { onAction(.refresh) } })
            if state.loading || state.busy { ProgressView(copy("loading")) }
            if !state.fresh { Text(copy("stale")).font(theme.captionFont) }
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
            ForEach(state.conversations) { row in Button(row.title) { onAction(.mode(.list(row.id))) } }
            Button(copy("create")) { onAction(.unavailable) }
        case .list(let conversation):
            Text(conversation).font(theme.captionFont)
            if state.rows.isEmpty && !state.loading && state.failure == nil { Text(copy("empty")) }
            ForEach(state.rows) { row in RFListRow(id: row.id, title: row.title, subtitle: status(row.status), theme: theme, leading: { Image(systemName: "checklist") }, trailing: { Image(systemName: "chevron.right") }) { onAction(.mode(.detail(conversation: row.conversationID, task: row.id))) } }
            if state.nextCursor != nil { Button(copy("more")) { onAction(.loadMore) }.disabled(state.loading || state.busy) }
        case .detail: EmptyView()
        case .permissions:
            Text(copy("noAuthority")).font(theme.captionFont)
            if state.permissions.isEmpty && !state.loading && state.failure == nil { Text(copy("empty")) }
            ForEach(state.permissions) { row in Button { onAction(.mode(.permission(row.id))) } label: {
                VStack(alignment: .leading) {
                    switch row {
                    case .grant(let grant): Text(grant.state.tool); Text(copy("grant")); Text(grant.state.server).font(theme.captionFont)
                    case .approval(let approval): Text(approval.tool); Text(copy("approval")); Text(approval.server).font(theme.captionFont)
                    case .receipt(let receipt): Text(copy("receipt")); Text(receipt.binding.taskID).font(theme.captionFont)
                    }
                }
            } }
        case .permission:
            if let row = state.selectedPermission {
                TaskPermissionDetails(row: row)
                Text(copy("noAuthority")); Button(copy("reviewPermission")) { onAction(.unavailable) }
            }
        }
    }
    private func facts(_ attempt: PendingTaskMutation) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            LabeledContent(copy("account"), value: state.accountID)
            LabeledContent(copy("conversation"), value: attempt.arguments.task.conversationID)
            LabeledContent(copy("task"), value: attempt.arguments.task.id)
            Text(attempt.arguments.task.title)
            LabeledContent(copy("version"), value: attempt.arguments.task.version.formatted(.number.locale(locale)))
            Text(copy(attempt.arguments.kind.rawValue)).font(theme.bodyFont.weight(.semibold))
        }
    }
}
