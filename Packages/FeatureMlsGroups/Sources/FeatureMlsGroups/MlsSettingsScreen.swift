// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// Group settings for the owner and admins: the name (1 to 64 grapheme clusters, trimmed; Save is its own confirmation) and
/// the approval switch (turning it off asks first). The name and the switch show the confirmed value from the group info,
/// never the requested one, until the `settings` event arrives; until then "Saving…" shows.
public struct MlsSettingsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupModel
    @State private var name = ""
    @State private var seeded = false
    @State private var confirmation: MlsAdminConfirmation?
    public init(model: MlsGroupModel) { self.model = model }
    private var saving: MlsSettingField? {
        if let busy = model.admin.busy, busy.kind == .settings, case .setting(let field) = busy.target { field } else { nil }
    }
    private var check: MlsAdminRules.NameCheck { MlsAdminRules.checkName(name) }
    private var canSave: Bool {
        guard case .ok(let clean) = check, let info = model.info else { return false }
        return clean != info.name && !model.entriesBlocked() && model.readOnly == nil
    }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(FeatureMlsGroupsStrings.text("group.settings.title", locale: locale), tag: "mls-settings-header")
            if let info = model.info {
                KitTextField(value: $name, label: FeatureMlsGroupsStrings.text("group.settings.name", locale: locale), error: nameError, enabled: saving != .name, tag: "mls-settings-name")
                HStack(spacing: theme.gap) {
                    KitButton(FeatureMlsGroupsStrings.text(saving == .name ? "group.settings.saving" : "group.settings.save", locale: locale), action: { if case .ok(let clean) = check { model.saveName(clean) } }, size: .compact, enabled: canSave, loading: saving == .name, tag: "mls-settings-save")
                }
                HStack(spacing: theme.gap) {
                    Text(FeatureMlsGroupsStrings.text("group.settings.approval", locale: locale)).rfFont(.body).frame(maxWidth: .infinity, alignment: .leading)
                    if saving == .approval { Text(FeatureMlsGroupsStrings.text("group.settings.saving", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-settings-approval-saving") }
                    KitSwitch(checked: info.approval, onChecked: { on in toggle(on, info) }, enabled: !model.entriesBlocked() && model.readOnly == nil, label: FeatureMlsGroupsStrings.text("group.settings.approval", locale: locale), tag: "mls-settings-approval")
                }
                if let notice = model.admin.notice {
                    Text(MlsChatText.error(notice.error, locale: locale)).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("mls-settings-error")
                }
                if model.admin.busy != nil, saving == nil { Text(FeatureMlsGroupsStrings.text("group.member.action.busy", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary) }
            } else { ProgressView() }
        }.padding(theme.gap) } }
        .task { model.start(); seedIfNeeded() }
        .onChange(of: model.info?.name) { _, _ in seedIfNeeded(force: !(saving == .name)) }
        .onDisappear { model.stop(); model.clearNotice() }
        .mlsAdminConfirm($confirmation) { model.perform($0) }
    }
    private var nameError: String? {
        switch check {
        case .empty: name.isEmpty ? nil : FeatureMlsGroupsStrings.text("group.create.nameRequired", locale: locale)
        case .tooLong: FeatureMlsGroupsStrings.text("group.create.nameTooLong", locale: locale)
        case .ok: nil
        }
    }
    /// The field starts at the confirmed name; a later confirmed name replaces it unless a save is running.
    private func seedIfNeeded(force: Bool = false) {
        guard let current = model.info?.name, !seeded || force else { return }
        name = current; seeded = true
    }
    private func toggle(_ on: Bool, _ info: MlsGroupInfo) {
        if on { model.turnApprovalOn() }
        else { confirmation = MlsAdminConfirmation(kind: .approvalOff, groupName: info.name) }
    }
}
