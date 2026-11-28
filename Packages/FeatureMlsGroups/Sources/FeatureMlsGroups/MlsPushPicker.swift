// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// The per-device notification picker of group info (r4 item 2). Every member of a group that is not read-only has it. The
/// check mark follows the confirmed value of `group.info`; a choice shows "Saving…" until the reply, and a failed choice
/// keeps the old value with a line. It is never a group setting and never a timeline row.
struct MlsPushPicker: View {
    let current: MlsPush
    let saving: MlsPush?
    let failed: Bool
    let onChoose: (MlsPush) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    private static let choices: [(MlsPush, String)] = [(.mentionsReplies, "mentions_replies"), (.all, "all"), (.none, "none")]
    var body: some View {
        VStack(alignment: .leading, spacing: theme.gap / 2) {
            Text(FeatureMlsGroupsStrings.text("group.push.title", locale: locale)).rfFont(.body, weight: .semibold)
            Text(FeatureMlsGroupsStrings.text("group.push.help", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            ForEach(Self.choices, id: \.1) { choice, tag in
                Button { if choice != current, saving == nil { onChoose(choice) } } label: {
                    HStack {
                        Text(MlsGroupsText.push(choice, locale: locale)).rfFont(.body)
                        Spacer()
                        if saving == choice { ProgressView().controlSize(.small) } else if choice == current { Image(systemName: "checkmark").foregroundStyle(theme.primary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(saving != nil).accessibilityIdentifier("mls-push-" + tag)
                    .accessibilityAddTraits(choice == current ? .isSelected : [])
            }
            if saving != nil { Text(FeatureMlsGroupsStrings.text("group.push.saving", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-push-saving") }
            if failed { Text(FeatureMlsGroupsStrings.text("group.push.failed", locale: locale)).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier("mls-push-failed") }
        }
    }
}
