// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// The locked state of a tab or screen: the accounts this device knows, each with its unlock action.
/// One layout for every locked surface (Messages, Groups, Agents, Contacts and the pushed screens).
public struct LockedAccountsBlock: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let accounts: [AccountRecord]
    let onUnlock: (String) -> Void
    public init(accounts: [AccountRecord], onUnlock: @escaping (String) -> Void) { self.accounts = accounts; self.onUnlock = onUnlock }
    public var body: some View {
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
                KitStatusHero(icon: "lock", tag: "shell-locked")
                Text(FeatureAppShellStrings.text("shell.locked.title", locale: locale)).rfFont(.body, weight: .semibold).foregroundStyle(theme.text)
                Text(FeatureAppShellStrings.text("shell.locked.message", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                ForEach(accounts) { account in
                    KitButton(RFSentence.compose(FeatureAppShellStrings.text("shell.locked.unlock", locale: locale), [.untrusted(account.displayName)], locale: locale),
                              action: { onUnlock(account.id) }, tag: "shell-unlock-account")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
