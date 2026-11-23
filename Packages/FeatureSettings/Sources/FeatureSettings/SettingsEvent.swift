// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum SettingsEvent: Equatable, Sendable { case navigate(AppRoute), locked, appearanceChanged(AppearanceMode)
    /// A backup was restored onto this install as a new account; it is unlocked with the code just set.
    case restored(String)
}
