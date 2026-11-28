// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign
#if canImport(UIKit)
import UIKit
#endif

/// Join with a link. The field is cleared when the sheet closes and after a join; Paste reads the clipboard only on the tap;
/// Join is one call per tap and is disabled while a call runs. The sheet shows only the outcome of its own attempt.
public struct MlsJoinSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupsCoordinator
    @State private var link = ""
    public init(model: MlsGroupsCoordinator) { self.model = model }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureMlsGroupsStrings.text("group.join.title", locale: locale)).rfFont(.page)
            KitTextField(value: $link, label: FeatureMlsGroupsStrings.text("group.join.field", locale: locale), enabled: !model.join.joining, tag: "mls-join-field")
            HStack(spacing: theme.gap) {
                KitButton(FeatureMlsGroupsStrings.text("group.join.paste", locale: locale), action: paste, kind: .secondary, size: .compact, enabled: !model.join.joining, tag: "mls-join-paste")
                KitButton(FeatureMlsGroupsStrings.text(model.join.joining ? "group.join.joining" : "group.join.submit", locale: locale), action: { model.joinTapped(link: link) }, size: .compact, enabled: !model.join.joining && !link.isEmpty, loading: model.join.joining, tag: "mls-join-submit")
            }
            if let outcome = model.join.outcome {
                VStack(alignment: .leading, spacing: theme.gap) {
                    Text(MlsGroupsText.outcome(outcome, groupName: model.joinedName, locale: locale)).rfFont(.body)
                        .foregroundStyle(isFailure(outcome) ? theme.danger : theme.text)
                    if let group = openable(outcome) {
                        KitButton(FeatureMlsGroupsStrings.text("group.join.open", locale: locale), action: { link = ""; model.openJoined(group) }, kind: .secondary, tag: "mls-join-open-group")
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("mls-join-outcome")
            }
            KitButton(FeatureMlsGroupsStrings.text("group.common.close", locale: locale), action: { link = ""; model.closeJoin() }, kind: .text, tag: "mls-join-close")
        }.padding(theme.gap) } }
        .onChange(of: model.join.outcome) { _, outcome in if case .joined? = outcome { link = "" } }
        .onDisappear { link = ""; model.closeJoin() }
    }
    private func paste() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string { link = text }
        #endif
    }
    private func isFailure(_ outcome: MlsJoinOutcome) -> Bool { switch outcome { case .refused, .failed: true; default: false } }
    private func openable(_ outcome: MlsJoinOutcome) -> String? {
        switch outcome {
        case .joined(let group): group
        case .refused(.alreadyMember(let group?), _): group
        default: nil
        }
    }
}
