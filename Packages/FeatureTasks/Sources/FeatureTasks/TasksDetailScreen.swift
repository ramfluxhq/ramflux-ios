// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
/// E02/E04 keep task facts and progress bounded between native navigation and action chrome.
struct TasksDetailScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let state: TasksState
    let row: TaskRecord
    let onAction: (TasksAction) -> Void
    private func copy(_ key: String) -> String { FeatureTasksStrings.text("tasks." + key, locale: locale) }
    private func status(_ value: String) -> String { copy(["proposed", "running", "needs_me", "done", "failed", "cancelled"].contains(value) ? value : "unknown") }
    private var enabled: Bool { state.fresh && !state.loading && !state.busy && state.pending == nil && !row.pendingResolution }
    var body: some View {
        RFPage { VStack(spacing: 0) {
            RFPageHeader(title: status(row.status), subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { Button(copy("refresh")) { onAction(.refresh) } })
            ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                Text(row.title).font(.custom(theme.font, size: theme.size_title).weight(.semibold))
                VStack(alignment: .leading, spacing: theme.gap) {
                    LabeledContent(copy("status"), value: status(row.status))
                    LabeledContent(copy("assignee"), value: row.assignee)
                    if let requester = row.requester { LabeledContent(copy("requester"), value: requester) }
                    LabeledContent(copy("conversation"), value: row.conversationID)
                    LabeledContent(copy("version"), value: row.version.formatted(.number.locale(locale)))
                }.padding(theme.gap).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
                if !row.steps.isEmpty {
                    VStack(alignment: .leading, spacing: theme.gap) {
                        ForEach(row.steps) { step in
                            VStack(alignment: .leading, spacing: theme.gap / 2) {
                                LabeledContent(step.title, value: status(step.status))
                                if step.interventionKind != nil { Button(copy("intervention")) { onAction(.unavailable) } }
                            }
                        }
                    }.padding(theme.gap).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
                }
                Text(copy("operationBoundary")).font(theme.captionFont).foregroundStyle(theme.secondary)
                if state.loading || state.busy { ProgressView(copy("loading")) }
                if !state.fresh { Text(copy("stale")) }
                if row.stalled { Text(copy("stalled")) }
                if row.pendingResolution { Text(copy("waiting")) }
                if let result = row.result { LabeledContent(copy("result"), value: result) }
                if let outcome = state.outcome { Text(copy(outcome.pending ? "waiting" : "submitted")) }
                if let pending = state.pending { Text(copy("pending")); Text(pending.arguments.task.title); Text(pending.arguments.task.id) }
                if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                Button(copy("conversations")) { onAction(.mode(.conversations)) }
            }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) }
        } }
        .safeAreaInset(edge: .bottom) {
            if let pending = state.pending {
                Button(copy("reconcile")) { onAction(.reconcile(pending.operationID)) }.disabled(state.busy).padding(theme.gap).frame(maxWidth: .infinity).background(theme.nav)
            } else if ["proposed", "running", "needs_me"].contains(row.status) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.gap / 2) { footerActions }
                    VStack(spacing: theme.gap / 2) { footerActions }
                }.padding(theme.gap).frame(maxWidth: .infinity).background(theme.nav)
            }
        }
    }
    @ViewBuilder private var footerActions: some View {
        RFActionButton(id: "task-cancel", label: copy("cancel"), kind: .secondary, disabled: !enabled, theme: theme) {
            onAction(.prepare(row.status == "proposed" ? .decline : .cancel))
        }
        RFActionButton(id: "task-primary", label: copy(row.status == "proposed" ? "startProposed" : "pendingItems"), kind: .primary, disabled: !enabled, theme: theme) {
            onAction(row.status == "proposed" ? .prepare(.accept) : .unavailable)
        }
    }
}
