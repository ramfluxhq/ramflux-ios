// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum AppShellAction: Sendable, Equatable {
    case appeared, disappeared, sceneActive, sceneInactive, sceneBackground, retry
    case selectTab(AppTab), open(AppRoute), openAccounts, selectAccount(String), deepLink(URL)
    /// Opens the code-only unlock of a known account the SDK has not opened.
    case unlockAccount(String)
    /// Opens `route` once `account` is the active, unlocked account and the privacy shield is down (a tapped
    /// notification): a locked or concealed session shows unlock first; another account becoming active drops it.
    case openWhenReady(AppRoute, account: String)
}
