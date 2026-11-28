// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// New group: a name of 1 to 64 characters, the approval switch (on by default) with its help, the size line.
public struct MlsCreateSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupsCoordinator
    @State private var name = ""
    @State private var approval = true
    public init(model: MlsGroupsCoordinator) { self.model = model }
    private var check: MlsGroupsText.NameCheck { MlsGroupsText.checkName(name) }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureMlsGroupsStrings.text("group.create.title", locale: locale)).rfFont(.page)
            KitTextField(value: $name, label: FeatureMlsGroupsStrings.text("group.create.name", locale: locale), error: nameError, enabled: !model.creating, tag: "mls-create-name")
            HStack {
                Text(FeatureMlsGroupsStrings.text("group.create.approval", locale: locale)).rfFont(.body)
                Spacer()
                KitSwitch(checked: approval, onChecked: { approval = $0 }, enabled: !model.creating, label: FeatureMlsGroupsStrings.text("group.create.approval", locale: locale), tag: "mls-create-approval")
            }
            Text(MlsGroupsText.approvalHelp(approval, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            Text(FeatureMlsGroupsStrings.text("group.create.size", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            if let error = model.createError {
                Text(MlsChatText.error(error, locale: locale)).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("mls-create-error")
            }
            KitButton(FeatureMlsGroupsStrings.text(model.creating ? "group.create.creating" : "group.create.submit", locale: locale), action: { model.create(name: name, approval: approval) }, enabled: { if case .ok = check { !model.creating } else { false } }(), loading: model.creating, tag: "mls-create-submit")
            KitButton(FeatureMlsGroupsStrings.text("group.common.cancel", locale: locale), action: { model.sheet = nil }, kind: .secondary, enabled: !model.creating, tag: "mls-create-cancel")
        }.padding(theme.gap) } }
        .interactiveDismissDisabled(model.creating)
    }
    private var nameError: String? {
        guard !name.isEmpty else { return nil }
        switch check {
        case .tooLong: return FeatureMlsGroupsStrings.text("group.create.nameTooLong", locale: locale)
        case .empty: return FeatureMlsGroupsStrings.text("group.create.nameRequired", locale: locale)
        case .ok: return nil
        }
    }
}
