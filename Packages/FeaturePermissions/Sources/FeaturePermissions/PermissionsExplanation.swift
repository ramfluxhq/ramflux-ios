// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct PermissionsExplanation: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let permission: DevicePermission
    public let busy: Bool
    public let onAction: (PermissionsAction) -> Void
    public init(permission: DevicePermission, busy: Bool, onAction: @escaping (PermissionsAction) -> Void) { self.permission = permission; self.busy = busy; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeaturePermissionsStrings.text(key, locale: locale) }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(copy(permission.rawValue + ".title")).font(theme.pageFont)
            Text(copy(permission.rawValue + ".why"))
            Text(copy(permission.rawValue + ".scope"))
            Text(copy(permission.rawValue + ".without"))
            Text(copy("promptBoundary")).font(theme.captionFont)
            RFHostConfirmationActions(summary: copy(permission.rawValue + ".title"), confirmLabel: copy("continue"), enabled: !busy, cancelEnabled: !busy, confirm: { onAction(.confirmExplanation) }, cancel: { onAction(.cancelExplanation) })
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
    }
}
