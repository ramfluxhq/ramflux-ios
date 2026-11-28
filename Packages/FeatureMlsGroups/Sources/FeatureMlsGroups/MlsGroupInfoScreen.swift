// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// Group info: name, counts, the `host_ip_visible` row, approval, the warning rows and the admission hint, the per-device push
/// picker, the invites entry with the commit quota line, the requests and settings entries (owner and admins), the members
/// entry, Refresh and Leave (confirmed). The invite entry shows for every member (r4 item 9).
public struct MlsGroupInfoScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupModel
    let onMembers: () -> Void
    let onInvites: () -> Void
    let onRequests: () -> Void
    let onSettings: () -> Void
    @State private var confirmLeave = false
    public init(model: MlsGroupModel, onMembers: @escaping () -> Void, onInvites: @escaping () -> Void, onRequests: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) { self.model = model; self.onMembers = onMembers; self.onInvites = onInvites; self.onRequests = onRequests; self.onSettings = onSettings }
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
                if MlsPrivacyRule.showsInfo(info.privacyDelay) {
                    Text(MlsChatText.privacyInfo(locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-info-privacy")
                }
                ForEach(Array(model.admin.warningRows.enumerated()), id: \.offset) { _, code in warningRow(code) }
                if model.readOnly == nil {
                    MlsPushPicker(current: info.push, saving: model.admin.pushSaving, failed: model.admin.pushFailed, onChoose: { model.choosePush($0) })
                    entry("group.invite.title", id: "mls-info-invites", action: onInvites)
                    if let quota = info.commitQuota, MlsQuotaRule.shows(quota) {
                        Text(MlsChatText.commitQuota(quota, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-info-quota-commit")
                    }
                }
                if model.showsRequests { requestsEntry }
                if model.showsSettings { entry("group.info.settingsEntry", id: "mls-settings-entry", action: onSettings) }
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
    /// The requests entry with its count: the loaded rows, "more than" while a next page exists (the info has no count).
    private var requestsEntry: some View {
        let requests = model.admin.requests
        let text = requests.more ? FeatureMlsGroupsStrings.format("group.requests.entryMore", requests.count, locale: locale) : FeatureMlsGroupsStrings.format("group.requests.entry", requests.count, locale: locale)
        return Button(action: onRequests) { HStack { Text(FeatureMlsGroupsStrings.text("group.info.requestsEntry", locale: locale)).rfFont(.body); Spacer(); Text(text).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-requests-count"); Image(systemName: "chevron.forward").foregroundStyle(theme.secondary) }.contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityIdentifier("mls-requests-entry")
    }
    /// A warning row repeats the banner text. The admission row also carries the hint for members of a group that is not read-only.
    @ViewBuilder private func warningRow(_ code: MlsWarningCode) -> some View {
        KitTipBar(MlsChatText.warning(code, locale: locale), icon: "info", tag: "mls-warning-" + code.name)
        if case .admissionNeedsOnline = code, model.readOnly == nil {
            VStack(alignment: .leading, spacing: 4) {
                Button(MlsChatText.hintInvite(locale: locale), action: onInvites).rfFont(.body).accessibilityIdentifier("mls-hint-invite")
                Text(MlsChatText.hintMobile(locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-hint-mobile")
            }
        }
    }
    private func entry(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(FeatureMlsGroupsStrings.text(key, locale: locale)).rfFont(.body); Spacer(); Image(systemName: "chevron.forward").foregroundStyle(theme.secondary) }.contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
