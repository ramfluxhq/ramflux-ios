// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct NotificationPermissionBanner: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: PermissionsState
    public let onAction: (PermissionsAction) -> Void
    public init(state: PermissionsState, onAction: @escaping (PermissionsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        if state.snapshot[.notifications] == .denied {
            VStack(alignment: .leading, spacing: theme.gap / 2) {
                Text(FeaturePermissionsStrings.text("notifications.off", locale: locale)).font(theme.captionFont)
                Button(FeaturePermissionsStrings.text("openSettings", locale: locale)) { onAction(.openSettings) }
            }.padding(theme.gap).frame(maxWidth: .infinity, alignment: .leading).background(theme.danger_bg)
        }
    }
}
