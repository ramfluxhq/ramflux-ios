// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// Group info: name, counts, the `host_ip_visible` row, approval and push (read-only), the invites entry, the members
/// entry, Refresh and Leave (confirmed). The invite entry shows for every member (r4 item 9).
public struct MlsGroupInfoScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupModel
    let onMembers: () -> Void
    let onInvites: () -> Void
    @State private var confirmLeave = false
    public init(model: MlsGroupModel, onMembers: @escaping () -> Void, onInvites: @escaping () -> Void) { self.model = model; self.onMembers = onMembers; self.onInvites = onInvites }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(FeatureMlsGroupsStrings.text("group.info.title", locale: locale), tag: "mls-info-header")
            if let info = model.info {
                Text(untrusted: info.name).rfFont(.page).accessibilityIdentifier("mls-info-name")
                Text(FeatureMlsGroupsStrings.format("group.info.members", info.members, locale: locale)).rfFont(.body)
                if info.agents > 0 {
                    HStack(spacing: theme.gap / 2) { KitAIMarker(tag: "mls-info-ai"); Text(FeatureMlsGroupsStrings.format("group.info.agents", info.agents, locale: locale)).rfFont(.body) }
                }
                if let host = info.visibleHost {
                    KitTipBar(FeatureMlsGroupsStrings.sentence("group.warning.hostIpVisible", [.untrusted(host)], locale: locale), icon: "info", tag: "mls-info-host-ip")
                }
                Text(FeatureMlsGroupsStrings.text(info.approval ? "group.info.approvalOn" : "group.info.approvalOff", locale: locale)).rfFont(.body)
                HStack { Text(FeatureMlsGroupsStrings.text("group.info.push", locale: locale)).rfFont(.body); Spacer(); Text(MlsGroupsText.push(info.push, locale: locale)).rfFont(.body).foregroundStyle(theme.secondary) }
                if model.readOnly == nil { entry("group.invite.title", id: "mls-info-invites", action: onInvites) }
                entry("group.info.membersEntry", id: "mls-info-members", action: onMembers)
            } else { ProgressView() }
            KitButton(FeatureMlsGroupsStrings.text("group.info.refresh", locale: locale), action: { model.refresh() }, kind: .secondary, tag: "mls-info-refresh")
            if let error = model.leaveError {
                Text(error == .ownerProtected ? FeatureMlsGroupsStrings.text("group.leave.owner", locale: locale) : MlsChatText.error(error, locale: locale)).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("mls-leave-error")
            }
            if let reason = model.readOnly { Text(MlsChatText.banner(reason, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-left") }
            else { KitButton(FeatureMlsGroupsStrings.text("group.info.leave", locale: locale), action: { confirmLeave = true }, kind: .destructive, enabled: !model.leaving, loading: model.leaving, tag: "mls-info-leave") }
        }.padding(theme.gap) } }
        .task { model.start() }
        .onDisappear { model.stop() }
        .confirmationDialog(FeatureMlsGroupsStrings.text("group.leave.title", locale: locale), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(FeatureMlsGroupsStrings.text("group.leave.confirm", locale: locale), role: .destructive) { model.leave() }.accessibilityIdentifier("mls-leave-confirm")
            Button(FeatureMlsGroupsStrings.text("group.common.cancel", locale: locale), role: .cancel) {}
        } message: { Text(FeatureMlsGroupsStrings.text("group.leave.body", locale: locale)) }
    }
    private func entry(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(FeatureMlsGroupsStrings.text(key, locale: locale)).rfFont(.body); Spacer(); Image(systemName: "chevron.forward").foregroundStyle(theme.secondary) }.contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
