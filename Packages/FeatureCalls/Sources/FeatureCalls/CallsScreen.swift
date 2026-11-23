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
        RFPage { ScrollView { LazyVStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(copy("title"), onBack: { dismiss() }, actionLabel: copy("history"), onAction: { onAction(.mode(.history)) }, actions: [KitHeaderAction(icon: "refresh-cw", label: copy("refresh"), action: { onAction(.refresh) })], tag: "calls-header")
            if state.loading { ProgressView(copy("loading")) }
            if state.busy { ProgressView(copy("applying")) }
            if let pending = state.pending {
                Text(copy("pending")).rfFont(.body, weight: .semibold)
                KitIdentifierText(pending.expected.peerID)
                Button(copy("reconcile")) { onAction(.reconcile(pending.operationID)) }.disabled(state.busy)
            }
            if !state.fresh && !state.calls.isEmpty { Text(copy("stale")).rfFont(.caption) }
            content
            if let failure = state.failure, !CallsScreen.ownsFailure(state) { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if state.mode == .history { Button(copy("permissions")) { onAction(.mode(.permissions)) } }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
        .privacySensitive().rfHidesNavigationBar()
    }
    /// The dial page draws its own offline and unavailable states (MOB-K08).
    static func ownsFailure(_ state: CallsState) -> Bool {
        guard case .dial = state.mode else { return false }
        return state.failure == .offline || state.failure == state.audioFailure
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .history:
            KitSearchField(value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), placeholder: copy("filter"), tag: "calls-filter")
            if state.visibleCalls.isEmpty && !state.loading && state.failure == nil {
                RFUnavailableView(title: copy("empty"), message: copy("empty.message"))
            }
            ForEach(state.visibleCalls) { row in
                CallHistoryRow(row: row, name: state.names[row.peerID]) { onAction(.mode(.detail(row.id))) }
                    .onAppear { if row.id == state.visibleCalls.last?.id, state.nextCursor != nil { onAction(.loadMore) } }
            }
        case .dial(let conversation): dial(conversation)
        case .detail:
            if let row = state.selected { detail(row) }
        case .permissions:
            Text(copy("permissions")).rfFont(.page)
            Text(copy("permission.message"))
            LabeledContent(copy("microphone"), value: copy(state.microphone == .unavailable ? "permissionUnavailable" : state.microphone.rawValue))
            Button(copy("settings")) { onAction(.openSettings) }
        }
    }
    /// MOB-K01 entry: start a call from a direct conversation, or say honestly why not.
    @ViewBuilder private func dial(_ conversation: String) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(copy("conversation")).rfFont(.caption).foregroundStyle(theme.secondary)
            KitIdentifierText(conversation, tag: "calls-dial-conversation")
            if state.failure == .offline {
                CallNotice(icon: "wifi-off", title: copy("offline.title"), message: copy("offline.message"), tone: .warning, tag: "calls-offline")
            } else if !state.canCall {
                CallNotice(icon: "phone-off", title: copy("unavailable.title"), message: copy("unavailable.message"), tone: .warning, tag: "calls-unavailable")
            }
            if let permission = state.permissionNeeded { CallPermissionNotice(permission: permission, onAction: onAction) }
            KitButton(copy("start.voice"), action: { onAction(.start) }, kind: .primary, enabled: state.canCall && !state.busy && state.pending == nil, loading: state.busy, tag: "calls-start-voice")
            // `call.invite` is voice-only in the SDK, so a video call cannot be started yet.
            KitButton(copy("start.video"), action: {}, kind: .secondary, enabled: false, tag: "calls-start-video")
            Text(copy("video.unavailable")).rfFont(.caption).foregroundStyle(theme.secondary)
        }
    }
    private func detail(_ row: CallRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            if let name = state.names[row.peerID] { Text(untrusted: name).rfFont(.body, weight: .semibold) }
            KitIdentifierText(row.peerID)
            Text(copy(row.phase.rawValue)).rfFont(.body, weight: .semibold)
            LabeledContent(copy("id")) { KitIdentifierText(row.id) }
            time("created", row.createdAt)
            if let answered = row.answeredAt { time("answered", answered) }
            if let ended = row.endedAt { time("endedAt", ended) }
            if let duration = row.duration { LabeledContent(copy("duration"), value: FeatureCallsStrings.duration(duration, locale: locale)) }
            if let reason = row.endReason { LabeledContent(copy("endReason"), value: copy(CallHistoryRow.knownReasons.contains(reason) ? reason : "reasonUnknown")) }
            if let reason = row.failureReason { LabeledContent(copy("localFailure"), value: copy(reason == .unknown ? "reasonUnknown" : reason.rawValue)) }
            if let reason = row.peerReason { LabeledContent(copy("peerFailure"), value: copy(reason == .unknown ? "reasonUnknown" : reason.rawValue)) }
        }
    }
    private func time(_ key: String, _ timestamp: Int64) -> some View {
        LabeledContent(copy(key), value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
    }
}

/// One history row: who (name if known, else the identifier), direction, outcome and
/// duration (or the start time for calls that never connected), from the SDK row alone.
struct CallHistoryRow: View {
    static let knownReasons: Set<String> = ["declined", "completed", "cancelled", "missed", "busy", "timeout", "failed", "answered_elsewhere"]
    @Environment(\.locale) private var locale
    let row: CallRecord
    let name: String?
    let open: () -> Void
    private func copy(_ key: String) -> String { FeatureCallsStrings.text("calls." + key, locale: locale) }
    var outcome: String {
        guard row.phase == .ended else { return copy(row.phase.rawValue) }
        guard let reason = row.endReason else { return copy("ended") }
        return copy(Self.knownReasons.contains(reason) ? reason : "reasonUnknown")
    }
    var icon: String {
        if row.phase == .ended, ["missed", "declined", "timeout", "failed", "busy"].contains(row.endReason ?? "") { return "phone-off" }
        return row.direction == .incoming ? "phone-incoming" : "phone"
    }
    var body: some View {
        let when = row.duration.map { FeatureCallsStrings.duration($0, locale: locale) }
            ?? Date(timeIntervalSince1970: TimeInterval(row.createdAt)).formatted(.dateTime.month().day().hour().minute().locale(locale))
        let label = name.map { RFUntrustedText.clean($0, kind: .identity) } ?? RFIdentifier.display(row.peerID)
        KitRow(label, action: open, icon: icon,
               value: FeatureCallsStrings.sentence("calls.row.detail", [.localized(copy(row.direction.rawValue)), .localized(outcome), .localized(when)], locale: locale), tag: row.id)
    }
}
