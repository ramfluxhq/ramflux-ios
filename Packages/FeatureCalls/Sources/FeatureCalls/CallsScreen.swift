// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization
public struct CallsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: CallsState
    public let onAction: (CallsAction) -> Void
    public init(state: CallsState, onAction: @escaping (CallsAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureCallsStrings.text("calls." + key, locale: locale) }
    public var body: some View {
        if case .detail = state.mode, let row = state.selected {
            CallSessionScreen(state: state, row: row, onAction: onAction) { detail(row) }
        } else { regularBody }
    }
    private var regularBody: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(copy("title"), onBack: { dismiss() }, actionLabel: copy("history"), onAction: { onAction(.mode(.history)) }, actions: [KitHeaderAction(icon: "refresh-cw", label: copy("refresh"), action: { onAction(.refresh) })], tag: "calls-header")
            if state.loading { ProgressView(copy("loading")) }
            if state.busy { ProgressView(copy("applying")) }
            if let failure = state.audioFailure { RFUnavailableView(title: copy("dial"), message: failure.message(locale: locale)) }
            if let pending = state.pending {
                Text(copy("pending")).font(theme.bodyFont.weight(.semibold))
                Text(pending.expected.peerID).textSelection(.enabled)
                LabeledContent(copy("id"), value: pending.expected.id)
                Button(copy("reconcile")) { onAction(.reconcile(pending.operationID)) }.disabled(state.busy)
            }
            if !state.fresh && !state.calls.isEmpty { Text(copy("stale")).font(theme.captionFont) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            Button(copy("permissions")) { onAction(.mode(.permissions)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
        .privacySensitive().rfHidesNavigationBar()
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .history:
            KitSearchField(value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), placeholder: copy("filter"), tag: "calls-filter")
            if state.visibleCalls.isEmpty && !state.loading && state.failure == nil {
                RFUnavailableView(title: copy("empty"), message: copy("empty.message"))
            }
            ForEach(state.visibleCalls) { row in
                KitRow(row.peerID, action: { onAction(.mode(.detail(row.id))) }, icon: "phone", value: FeatureCallsStrings.sentence("calls.row.summary", [.localized(copy(row.direction.rawValue)), .localized(copy(row.phase.rawValue))], locale: locale), tag: row.id)
            }
        case .dial(let conversation):
            LabeledContent(copy("conversation"), value: conversation)
            Button(copy("start"), systemImage: "phone") { onAction(.start) }.disabled(state.busy || state.pending != nil)
        case .detail:
            if let row = state.selected { detail(row) }
        case .permissions:
            Text(copy("permissions")).font(theme.pageFont)
            Text(copy("permission.message"))
            LabeledContent(copy("microphone"), value: copy(state.microphone == .unavailable ? "permissionUnavailable" : state.microphone.rawValue))
            Button(copy("settings")) { onAction(.openSettings) }
        }
    }
    private func detail(_ row: CallRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(row.peerID).font(theme.pageFont).textSelection(.enabled)
            Text(copy(row.phase.rawValue)).font(theme.bodyFont.weight(.semibold))
            Text(copy("noAudio")).font(theme.captionFont)
            LabeledContent(copy("id"), value: row.id)
            time("created", row.createdAt)
            if let answered = row.answeredAt { time("answered", answered) }
            if let ended = row.endedAt { time("endedAt", ended) }
            if let answered = row.answeredAt, let ended = row.endedAt, ended >= answered {
                LabeledContent(copy("duration"), value: FeatureCallsStrings.duration(ended - answered, locale: locale))
            }
            if let reason = row.endReason { LabeledContent(copy("endReason"), value: copy(["declined", "completed", "cancelled", "missed", "busy", "timeout", "failed", "answered_elsewhere"].contains(reason) ? reason : "reasonUnknown")) }
            if let reason = row.failureReason { LabeledContent(copy("localFailure"), value: copy(reason == .unknown ? "reasonUnknown" : reason.rawValue)) }
            if let reason = row.peerReason { LabeledContent(copy("peerFailure"), value: copy(reason == .unknown ? "reasonUnknown" : reason.rawValue)) }

        }
    }
    private func time(_ key: String, _ timestamp: Int64) -> some View {
        LabeledContent(copy(key), value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
    }
}
