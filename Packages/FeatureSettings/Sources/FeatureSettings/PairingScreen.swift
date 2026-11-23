// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// Link a new device from this phone (board MOB-G24), compare the symbols, review the joining device's
/// facts before approval (MOB-P02/P02S rows) and show the end state (MOB-P04/P05 tone).
public struct PairingScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: PairingState
    public let onAction: (PairingAction) -> Void
    public init(state: PairingState, onAction: @escaping (PairingAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitPageHeader(copy("pairing.title"), onBack: { dismiss() }, tag: "pairing-header")
            ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                content
                if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            }.padding(.horizontal, theme.gap).padding(.vertical, theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) }
            actions.padding(theme.gap).frame(maxWidth: theme.column_max)
        } }
        .privacySensitive().rfHidesNavigationBar()
        .overlay { if state.covered, case .invitation = state.step { cover } }
        .sheet(isPresented: Binding(get: { state.confirmingApproval }, set: { if !$0 { onAction(.cancelApprove) } })) {
            if case .review(let progress) = state.step {
                RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(copy("pairing.approve.confirm.title")).rfFont(.page)
                    facts(progress)
                    RFHostConfirmationActions(summary: FeatureSettingsStrings.sentence("pairing.approve.confirm.summary", [.untrusted(progress.peerName ?? ""), .identifier(progress.peerDeviceID ?? "")], locale: locale),
                                              confirmLabel: copy("pairing.approve.confirm.action"), enabled: !state.busy, cancelEnabled: !state.busy,
                                              confirm: { onAction(.confirmApprove) }, cancel: { onAction(.cancelApprove) }).id(progress.proposalHash ?? "")
                }.padding(theme.gap) } }.interactiveDismissDisabled(state.busy)
            }
        }
    }
    @ViewBuilder private var content: some View {
        switch state.step {
        case .name:
            Text(copy("pairing.name.body")).foregroundStyle(theme.secondary)
            KitTextField(value: Binding(get: { state.deviceName }, set: { onAction(.setName($0)) }), label: copy("pairing.name.label"), placeholder: copy("pairing.name.placeholder"),
                         note: copy("pairing.name.note"), enabled: !state.busy, tag: "pairing-name")
            KitTipBar(copy("pairing.join.unavailable"), icon: "info", tag: "pairing-join-unavailable")
        case .invitation(let code):
            Text(copy("pairing.invitation.body")).foregroundStyle(theme.secondary)
            KitQrCode(code.image, label: copy("pairing.invitation.qrLabel"), tag: "pairing-qr").frame(maxWidth: .infinity)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(FeatureSettingsStrings.format("pairing.invitation.expires", Self.remaining(until: code.expiresAt, now: context.date), locale: locale))
                    .rfFont(.caption).foregroundStyle(theme.secondary).frame(maxWidth: .infinity)
            }
            KitTipBar(copy("pairing.invitation.secret"), icon: "shield-alert", tag: "pairing-secret")
            KitTipBar(copy("pairing.waiting.joiner"), icon: "loader-circle", loading: true, tag: "pairing-waiting")
        case .compare(let progress):
            Text(copy("pairing.compare.title")).rfFont(.body, weight: .semibold)
            Text(copy("pairing.compare.body")).foregroundStyle(theme.secondary)
            KitPairingCode(Self.symbols(progress.emoji ?? []), tag: "pairing-symbols")
            facts(progress)
        case .waiting(let progress):
            KitTipBar(copy(Self.waitingKey(progress.phase)), icon: "loader-circle", loading: true, tag: "pairing-waiting")
            if progress.peerName != nil { facts(progress) }
        case .review(let progress):
            Text(copy("pairing.review.title")).rfFont(.body, weight: .semibold)
            Text(copy("pairing.review.body")).foregroundStyle(theme.secondary)
            facts(progress)
            KitSecurityWarning(copy("pairing.review.warning.title"), body: copy("pairing.review.warning.body"), tone: .warning, tag: "pairing-review-warning")
        case .finished(let progress):
            VStack(spacing: theme.gap) {
                KitStatusHero(icon: progress.phase == .completed ? "circle-check" : "circle-x", tint: progress.phase == .completed ? theme.success : theme.secondary, tag: "pairing-result")
                Text(copy(Self.finishedTitle(progress.phase))).rfFont(.page).multilineTextAlignment(.center)
                Text(copy(Self.finishedBody(progress))).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
        case .stopped:
            KitStatusHero(icon: "circle-alert", tag: "pairing-stopped").frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private var actions: some View {
        switch state.step {
        case .name:
            KitButton(copy("pairing.name.create"), action: { onAction(.begin) }, enabled: !state.busy && !state.deviceName.trimmingCharacters(in: .whitespaces).isEmpty, loading: state.busy, tag: "pairing-create")
        case .invitation, .waiting:
            KitButton(copy("pairing.cancel"), action: { onAction(.cancel) }, kind: .secondary, enabled: !state.busy, tag: "pairing-cancel")
        case .compare:
            VStack(spacing: theme.gap / 2) {
                KitButton(copy("pairing.compare.match"), action: { onAction(.symbolsMatch(true)) }, enabled: !state.busy, loading: state.busy, tag: "pairing-match")
                KitButton(copy("pairing.compare.mismatch"), action: { onAction(.symbolsMatch(false)) }, kind: .secondary, enabled: !state.busy, tag: "pairing-mismatch")
            }
        case .review:
            VStack(spacing: theme.gap / 2) {
                KitButton(copy("pairing.review.approve"), action: { onAction(.requestApprove) }, enabled: !state.busy, loading: state.busy, tag: "pairing-approve")
                KitButton(copy("pairing.review.decline"), action: { onAction(.decline) }, kind: .secondary, enabled: !state.busy, tag: "pairing-decline")
            }
        case .finished(let progress) where progress.phase == .completed:
            KitButton(copy("pairing.done"), action: { onAction(.done); dismiss() }, tag: "pairing-done")
        case .finished, .stopped:
            KitButton(copy("pairing.restart"), action: { onAction(.restart) }, kind: .secondary, tag: "pairing-restart")
        }
    }
    /// The joining device's facts: its name is peer-controlled text, its id a compared identifier.
    private func facts(_ progress: PairingProgress) -> some View {
        VStack(alignment: .leading, spacing: theme.gap / 2) {
            if let name = progress.peerName {
                Text(copy("pairing.facts.name")).rfFont(.caption).foregroundStyle(theme.secondary)
                Text(untrusted: name).rfFont(.body, weight: .semibold)
            }
            if let device = progress.peerDeviceID {
                Text(copy("pairing.facts.device")).rfFont(.caption).foregroundStyle(theme.secondary)
                KitIdentifierText(device, tag: "pairing-device-id")
            }
            Text(copy("pairing.facts.rights")).rfFont(.caption).foregroundStyle(theme.secondary)
            ForEach(progress.capabilities, id: \.self) { Text(copy(Self.capabilityKey($0))) }
            if progress.leaseExpiresAt > progress.leaseNotBefore {
                Text(FeatureSettingsStrings.format("pairing.facts.lease", progress.leaseExpiresAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)), locale: locale))
                    .rfFont(.caption).foregroundStyle(theme.secondary)
            }
        }
        .padding(theme.gap).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
    }
    private var cover: some View {
        VStack(spacing: theme.gap) {
            KitStatusHero(icon: "lock", tag: "pairing-covered")
            Text(copy("pairing.invitation.covered")).multilineTextAlignment(.center).foregroundStyle(theme.secondary)
        }
        .padding(theme.gap).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.bg)
    }
    private func copy(_ key: String) -> String { FeatureSettingsStrings.text(key, locale: locale) }
    /// The SDK's seven SAS symbols (`ramflux_crypto::custody::pairing::SAS_EMOJI`), compared visually on both devices.
    static func symbols(_ indices: [Int]) -> String { indices.compactMap { PairingSymbols.glyph($0) }.joined(separator: " ") }
    static func remaining(until end: Date, now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    static func capabilityKey(_ capability: String) -> String {
        switch capability { case "message": "pairing.right.message"; case "register": "pairing.right.register"; case "sync": "pairing.right.sync"; case "call": "pairing.right.call"; case "group": "pairing.right.group"; default: "pairing.right.other" }
    }
    static func waitingKey(_ phase: PairingPhase) -> String {
        switch phase {
        case .invited, .commitments: "pairing.waiting.joiner"
        case .revealed, .sasPending, .mutuallyConfirmed: "pairing.waiting.peerConfirm"
        case .proposalPending: "pairing.waiting.proposal"
        default: "pairing.waiting.install"
        }
    }
    static func finishedTitle(_ phase: PairingPhase) -> String {
        switch phase { case .completed: "pairing.finished.completed"; case .expired: "pairing.finished.expired"; case .rejected: "pairing.finished.rejected"; default: "pairing.finished.cancelled" }
    }
    static func finishedBody(_ progress: PairingProgress) -> String {
        if progress.phase == .completed { return "pairing.finished.completed.body" }
        if progress.result == PairingIssue.sasMismatch.rawValue { return "pairing.failure.SasMismatch.body" }
        switch progress.phase { case .expired: return "pairing.finished.expired.body"; case .rejected: return "pairing.finished.rejected.body"; default: return "pairing.finished.cancelled.body" }
    }
}
