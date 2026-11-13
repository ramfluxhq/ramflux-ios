// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum AppShellAction: Sendable, Equatable {
    case appeared, disappeared, sceneActive, sceneInactive, sceneBackground, retry
    case selectTab(AppTab), open(AppRoute), openAccounts, selectAccount(String), deepLink(URL)
}
