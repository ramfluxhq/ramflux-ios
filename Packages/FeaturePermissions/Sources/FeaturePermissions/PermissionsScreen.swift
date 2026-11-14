// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct PermissionsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: PermissionsState
    public let onAction: (PermissionsAction) -> Void
    public init(state: PermissionsState, onAction: @escaping (PermissionsAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeaturePermissionsStrings.text(key, locale: locale) }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            RFPageHeader(title: copy("title"), subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { EmptyView() })
            Text(copy("intro")).font(theme.captionFont)
            ForEach(DevicePermission.allCases) { permission in
                VStack(alignment: .leading, spacing: theme.gap / 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(copy(permission.rawValue)).font(theme.bodyFont.weight(.semibold))
                        Spacer()
                        Text(copy("status." + state.snapshot[permission].rawValue)).font(theme.captionFont)
                    }
                    Text(copy(permission.rawValue + ".detail")).font(theme.captionFont).foregroundStyle(theme.secondary)
                }.padding(theme.gap).background(theme.surface_white, in: .rect(cornerRadius: theme.radius_card))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("permission-status-" + permission.rawValue)
            }
            if state.busy { ProgressView(copy("loading")) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            Button(copy("openSettings")) { onAction(.openSettings) }.disabled(state.busy)
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
        .navigationTitle(copy("title"))
    }
}
