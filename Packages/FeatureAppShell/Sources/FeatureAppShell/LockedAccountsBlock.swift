// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// A pushed screen opened while no account is open and the device lists none to unlock: what to do next, and the way to
/// the account picker. (A locked account shows its lock page instead, see `AccountLockPage`.)
public struct LockedScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let message: String
    let onAccounts: () -> Void
    public init(message: String, onAccounts: @escaping () -> Void) { self.message = message; self.onAccounts = onAccounts }
    public var body: some View {
        RFPage {
            ScrollView {
                VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
                    KitStatusHero(icon: "lock", tag: "shell-locked")
                    Text(FeatureAppShellStrings.text("shell.accounts.empty.title", locale: locale)).rfFont(.body, weight: .semibold).foregroundStyle(theme.text)
                    Text(message).rfFont(.caption).foregroundStyle(theme.secondary)
                    KitButton(FeatureAppShellStrings.text("shell.accounts.title", locale: locale), action: onAccounts, kind: .primary, tag: "shell-accounts")
                }
                .padding(KitMetrics.gutter)
                .frame(maxWidth: theme.column_max, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("locked-screen")
    }
}
