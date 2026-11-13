// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
/// K01–K03: the identity/control body scrolls while call-ending actions remain in the safe area.
struct CallSessionScreen<Facts: View>: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let state: CallsState
    let row: CallRecord
    let onAction: (CallsAction) -> Void
    @ViewBuilder let facts: () -> Facts
    private func copy(_ key: String) -> String { FeatureCallsStrings.text("calls." + key, locale: locale) }
    var body: some View {
        RFPage { ScrollView { VStack(spacing: theme.gap) {
            RFPageHeader(title: copy("dial"), subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { Button(copy("history")) { onAction(.mode(.history)) } })
            VStack(spacing: theme.gap) {
                Text(String(row.peerID.prefix(1))).font(.custom(theme.font, size: theme.size_metric)).foregroundStyle(theme.on_avatar_person)
                    .frame(width: theme.row_conversation + theme.gap, height: theme.row_conversation + theme.gap).background(theme.avatar_person, in: Circle()).accessibilityHidden(true)
                Text(row.peerID).font(.custom(theme.font, size: theme.size_page).weight(.semibold)).textSelection(.enabled)
                Text(copy(row.phase.rawValue)).font(theme.bodyFont).foregroundStyle(theme.secondary)
            }.frame(maxWidth: .infinity, minHeight: theme.row_conversation * 3 + theme.size_page).padding(.vertical, theme.gap)
            if let unavailable = state.audioFailure { RFUnavailableView(title: copy("dial"), message: unavailable.message(locale: locale)) }
            Text(copy("noAudio")).font(theme.captionFont)
            if !state.fresh { Text(copy("stale")) }
            if row.phase == .active || row.phase == .connecting {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.gap) { audioControls }
                    VStack(spacing: theme.gap) { audioControls }
                }.padding(.vertical, theme.gap)
            }
            if state.busy { ProgressView(copy("applying")) }
            if let pending = state.pending { Text(copy("pending")); Button(copy("reconcile")) { onAction(.reconcile(pending.operationID)) }.disabled(state.busy) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            DisclosureGroup(copy("history")) { facts() }
        }.padding(theme.gap).frame(maxWidth: theme.column_max).frame(maxWidth: .infinity) } }
        .safeAreaInset(edge: .bottom) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.gap) { primaryActions }
                VStack(spacing: theme.gap) { primaryActions }
            }.padding(theme.gap).frame(maxWidth: .infinity).background(theme.bg)
        }.privacySensitive()
    }
    @ViewBuilder private var audioControls: some View {
        ForEach(["mute", "speaker", "share"], id: \.self) { key in
            Button { onAction(.audioControl) } label: { VStack(spacing: theme.gap / 2) {
                Image(systemName: key == "mute" ? "mic.slash" : key == "speaker" ? "speaker.wave.2" : "rectangle.on.rectangle")
                    .font(theme.bodyFont).padding(theme.gap).background(theme.surface, in: Circle())
                Text(copy(key)).font(theme.captionFont)
            } }.buttonStyle(.plain).accessibilityHint(state.audioFailure?.message(locale: locale) ?? copy("noAudio"))
        }
    }
    @ViewBuilder private var primaryActions: some View {
        if row.canDecline {
            action("decline", symbol: "phone.down.fill", destructive: true, enabled: state.canDecline) { onAction(.signal(.decline, callID: row.id, sequence: row.sequence)) }
            action("answer", symbol: "phone.fill", destructive: false, enabled: !state.busy && state.pending == nil) { onAction(.answer) }
        } else if row.canHangup {
            action("hangup", symbol: "phone.down.fill", destructive: true, enabled: state.canHangup) { onAction(.signal(.hangup, callID: row.id, sequence: row.sequence)) }
        }
    }
    private func action(_ key: String, symbol: String, destructive: Bool, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { VStack(spacing: theme.gap / 2) {
            Image(systemName: symbol).font(theme.bodyFont).foregroundStyle(destructive ? theme.on_danger : theme.on_success)
                .frame(width: theme.row_conversation, height: theme.row_conversation).background(destructive ? theme.danger : theme.success, in: Circle())
            Text(copy(key)).font(theme.bodyFont)
        }.frame(maxWidth: .infinity) }.buttonStyle(.plain).disabled(!enabled)
    }
}
