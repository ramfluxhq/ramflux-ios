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

/// A pushed screen opened while no account is unlocked: the same locked block as the tabs, with the
/// unlock action of each known account, or the account switcher when the device knows none.
public struct LockedScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let accounts: [AccountRecord]
    let message: String
    let onUnlock: (String) -> Void
    let onAccounts: () -> Void
    public init(accounts: [AccountRecord], message: String, onUnlock: @escaping (String) -> Void, onAccounts: @escaping () -> Void) {
        self.accounts = accounts; self.message = message; self.onUnlock = onUnlock; self.onAccounts = onAccounts
    }
    public var body: some View {
        RFPage {
            ScrollView {
                VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
                    if accounts.isEmpty {
                        KitStatusHero(icon: "lock", tag: "shell-locked")
                        Text(FeatureAppShellStrings.text("shell.locked.title", locale: locale)).rfFont(.body, weight: .semibold).foregroundStyle(theme.text)
                        Text(message).rfFont(.caption).foregroundStyle(theme.secondary)
                    } else {
                        LockedAccountsBlock(accounts: accounts, onUnlock: onUnlock)
                    }
                    KitButton(FeatureAppShellStrings.text("shell.accounts.title", locale: locale), action: onAccounts, kind: accounts.isEmpty ? .primary : .secondary, tag: "shell-accounts")
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
