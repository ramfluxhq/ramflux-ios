// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum AppShellEvent: Equatable, Sendable {
    case navigate(AppRoute), showAccounts, accountSelected, dismissPrivateNavigation
}
