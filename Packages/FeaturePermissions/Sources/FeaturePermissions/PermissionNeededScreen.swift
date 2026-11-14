// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct PermissionNeededScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let permission: DevicePermission
    public let busy: Bool
    public let onAction: (PermissionsAction) -> Void
    public init(permission: DevicePermission, busy: Bool, onAction: @escaping (PermissionsAction) -> Void) { self.permission = permission; self.busy = busy; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeaturePermissionsStrings.text(key, locale: locale) }
    public var body: some View {
        RFPage { VStack(alignment: .leading, spacing: theme.gap) {
            Text(copy(permission.rawValue + ".needed")).font(theme.pageFont)
            Text(copy(permission.rawValue + ".without"))
            Text(copy("denied"))
            Button(copy("cancel"), role: .cancel) { onAction(.dismissNeeded) }.disabled(busy)
            Button(copy("openSettings")) { onAction(.openSettings) }.disabled(busy)
        }.padding(theme.gap) }
    }
}
