// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// MOB-K01–K05, K09: outgoing, incoming, in call, permission needed, connection lost and call
/// failed. The identity and control body scrolls; call-ending actions stay in the safe area.
/// Media controls are always present and enabled only for what the engine can do.
struct CallSessionScreen<Facts: View>: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let state: CallsState
    let row: CallRecord
    let onAction: (CallsAction) -> Void
    @ViewBuilder let facts: () -> Facts
    private func copy(_ key: String) -> String { FeatureCallsStrings.text("calls." + key, locale: locale) }
    private var stage: CallStage { state.stage ?? .ended }
    var body: some View {
        RFPage { ScrollView { VStack(spacing: theme.gap) {
            KitPageHeader(copy(stage == .incoming ? "stage.incoming" : "dial"), onBack: { onAction(.mode(.history)) }, actionLabel: copy("history"), onAction: { onAction(.mode(.history)) }, tag: "call-session-header")
            identity
            if state.media.capabilities?.video == true, state.remoteVideo || state.camera { CallVideoArea(callID: row.id, local: state.camera, remote: state.remoteVideo) }
            notices
            if [.connecting, .inCall, .connectionLost].contains(stage) { controls }
            if state.busy { ProgressView(copy("applying")) }
            if let pending = state.pending { Text(copy("pending")); Button(copy("reconcile")) { onAction(.reconcile(pending.operationID)) }.disabled(state.busy) }
            if let failure = state.failure, failure != state.audioFailure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if !state.fresh { Text(copy("stale")).rfFont(.caption) }
            DisclosureGroup(copy("history")) { facts() }
        }.padding(theme.gap).frame(maxWidth: theme.column_max).frame(maxWidth: .infinity) } }
        .safeAreaInset(edge: .bottom) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.gap) { primaryActions }
                VStack(spacing: theme.gap) { primaryActions }
            }.padding(theme.gap).frame(maxWidth: .infinity).background(theme.bg)
        }.privacySensitive()
    }
    private var identity: some View {
        VStack(spacing: theme.gap) {
            KitAvatar(String((state.names[row.peerID] ?? row.peerID).prefix(1)), size: KitMetrics.conversation + theme.gap * 2, kind: .person).accessibilityHidden(true)
            if let name = state.names[row.peerID] { Text(untrusted: name).rfFont(.size(theme.size_page), weight: .semibold).multilineTextAlignment(.center) }
            KitIdentifierText(row.peerID, tag: "call-session-peer")
            stageLine
        }.frame(maxWidth: .infinity).padding(.vertical, theme.gap)
    }
    @ViewBuilder private var stageLine: some View {
        if stage == .inCall, let answered = row.answeredAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int64(context.date.timeIntervalSince1970) - answered)
                Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond).locale(locale))).rfFont(.body).foregroundStyle(theme.secondary).monospacedDigit()
            }
        } else {
            Text(copy(stageKey)).rfFont(.body).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
        }
    }
    private var stageKey: String {
        switch stage {
        case .outgoing: "stage.outgoing"
        case .incoming: "stage.incoming"
        case .connecting: "stage.connecting"
        case .inCall: "stage.inCall"
        case .connectionLost: "stage.connectionLost"
        case .ended: "stage.ended"
        case .failed: "stage.failed"
        }
    }
    @ViewBuilder private var notices: some View {
        if let permission = state.permissionNeeded { CallPermissionNotice(permission: permission, onAction: onAction) }
        switch stage {
        case .incoming where !state.canCall:
            CallNotice(icon: "phone-off", title: copy("unavailable.title"), message: copy("incoming.cannotAnswer"), tone: .warning, tag: "call-incoming-unavailable")
        case .connectionLost:
            CallNotice(icon: "wifi-off", title: copy("connectionLost.title"), message: copy("connectionLost.message"), tone: .warning, tag: "call-connection-lost")
        case .failed:
            CallNotice(icon: "circle-alert", title: copy("failed.title"), message: row.failureReason.map { copy($0 == .unknown ? "reasonUnknown" : $0.rawValue) } ?? copy("failed.message"), tone: .danger, tag: "call-failed")
        case .outgoing, .connecting, .inCall:
            if !state.canCall { CallNotice(icon: "phone-off", title: copy("unavailable.title"), message: copy("unavailable.message"), tone: .warning, tag: "call-media-unavailable") }
        case .incoming, .ended: EmptyView()
        }
    }
    private var controls: some View {
        let capabilities = state.media.capabilities
        let live = row.phase == .active
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: KitMetrics.conversation + theme.gap), spacing: theme.gap)], spacing: theme.gap) {
            control(state.muted ? "control.unmute" : "control.mute", icon: state.muted ? "mic-off" : "mic", on: state.muted, enabled: live && capabilities?.audio == true) { onAction(.control(.mute(!state.muted))) }
            control("control.speaker", icon: "volume-2", on: state.route == .speaker, enabled: live && capabilities?.speakerRoute == true) { onAction(.control(.route(state.route == .speaker ? .receiver : .speaker))) }
            control(state.camera ? "control.cameraOff" : "control.camera", icon: state.camera ? "video" : "camera-off", on: state.camera, enabled: live && capabilities?.video == true) { onAction(.control(.camera(!state.camera))) }
            control("control.switchCamera", icon: "refresh-cw", on: false, enabled: live && state.camera && capabilities?.cameraSwitch == true) { onAction(.control(.switchCamera)) }
        }.padding(.vertical, theme.gap)
    }
    private func control(_ key: String, icon: String, on: Bool, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: theme.gap / 2) {
                KitIcon(name: icon, size: KitMetrics.iconAction, tint: on ? theme.bg : theme.text)
                    .frame(width: KitMetrics.buttonHeight, height: KitMetrics.buttonHeight)
                    .background(on ? theme.text : theme.surface, in: Circle())
                Text(copy(key)).rfFont(.caption).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : KitMetrics.disabledAlpha)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(enabled ? "" : (state.audioFailure.map { _ in copy("unavailable.message") } ?? copy("control.unsupported")))
    }
    @ViewBuilder private var primaryActions: some View {
        if row.canDecline {
            action("decline", icon: "phone-off", destructive: true, enabled: state.canDecline) { onAction(.signal(.decline, callID: row.id, sequence: row.sequence)) }
            // Answer stays visible on MOB-K02 but is enabled only when this phone can carry audio.
            action("answer", icon: "phone", destructive: false, enabled: state.canAnswer) { onAction(.answer) }
        } else if row.canHangup {
            action("hangup", icon: "phone-off", destructive: true, enabled: state.canHangup) { onAction(.signal(.hangup, callID: row.id, sequence: row.sequence)) }
        }
    }
    private func action(_ key: String, icon: String, destructive: Bool, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { VStack(spacing: theme.gap / 2) {
            KitIcon(name: icon, size: KitMetrics.iconAction, tint: destructive ? theme.on_danger : theme.on_success)
                .frame(width: theme.row_conversation, height: theme.row_conversation).background(destructive ? theme.danger : theme.success, in: Circle())
            Text(copy(key)).rfFont(.body)
        }.frame(maxWidth: .infinity) }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : KitMetrics.disabledAlpha)
    }
}

/// A call state notice (MOB-K05, K08, K09 and the unavailable explanation).
struct CallNotice: View {
    let icon: String
    let title: String
    let message: String
    let tone: KitWarningTone
    let tag: String
    var body: some View { KitSecurityWarning(title, body: message, tone: tone, icon: icon, tag: tag) }
}

/// MOB-K04: the user declined a device permission the call needs; offer the system settings.
struct CallPermissionNotice: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let permission: DevicePermission
    let onAction: (CallsAction) -> Void
    private func copy(_ key: String) -> String { FeatureCallsStrings.text("calls." + key, locale: locale) }
    var body: some View {
        let camera = permission == .camera
        VStack(alignment: .leading, spacing: theme.gap) {
            KitStatusHero(icon: camera ? "camera-off" : "mic-off", tag: "call-permission-hero")
            Text(copy(camera ? "permission.camera.title" : "permission.microphone.title")).rfFont(.body, weight: .semibold)
            Text(copy(camera ? "permission.camera.message" : "permission.microphone.message")).rfFont(.body).foregroundStyle(theme.secondary)
            KitButton(copy("settings"), action: { onAction(.openSettings) }, kind: .primary, size: .compact, tag: "call-permission-settings")
            KitButton(copy("permission.notNow"), action: { onAction(.dismissPermission) }, kind: .text, size: .compact, tag: "call-permission-dismiss")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.gap).background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_card))
    }
}
