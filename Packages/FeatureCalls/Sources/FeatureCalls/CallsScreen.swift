// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct CallsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: CallsState
    public let onAction: (CallsAction) -> Void
    public init(state: CallsState, onAction: @escaping (CallsAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureCallsStrings.text("calls." + key, locale: locale) }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            RFPageHeader(title: copy("title"), subtitle: "", theme: theme, leading: { EmptyView() }, trailing: {
                Button(copy("history")) { onAction(.mode(.history)) }
            })
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
        .privacySensitive().toolbar { Button(copy("refresh"), systemImage: "arrow.clockwise") { onAction(.refresh) } }
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .history:
            RFSearchField(id: "calls-filter", label: copy("filter"), value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), theme: theme)
            if state.visibleCalls.isEmpty && !state.loading && state.failure == nil {
                RFStateBlock(title: copy("empty"), description: copy("empty.message"), kind: .empty, theme: theme) { EmptyView() }
            }
            ForEach(state.visibleCalls) { row in
                RFListRow(id: row.id, title: row.peerID, subtitle: copy(row.direction.rawValue) + " · " + copy(row.phase.rawValue), theme: theme,
                    leading: { Image(systemName: "phone") }, trailing: { Image(systemName: "chevron.right") }) { onAction(.mode(.detail(row.id))) }
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
            if row.canDecline {
                Button(copy("answer"), systemImage: "phone") { onAction(.answer) }.disabled(state.busy || state.pending != nil)
                Button(copy("decline"), role: .destructive) { onAction(.signal(.decline, callID: row.id, sequence: row.sequence)) }.disabled(!state.canDecline)
            }
            if row.canHangup { Button(copy("hangup"), role: .destructive) { onAction(.signal(.hangup, callID: row.id, sequence: row.sequence)) }.disabled(!state.canHangup) }
            if row.phase == .active || row.phase == .connecting {
                ForEach(["mute", "speaker", "share"], id: \.self) { key in Button(copy(key)) { onAction(.audioControl) } }
            }
        }
    }
    private func time(_ key: String, _ timestamp: Int64) -> some View {
        LabeledContent(copy(key), value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
    }
}
