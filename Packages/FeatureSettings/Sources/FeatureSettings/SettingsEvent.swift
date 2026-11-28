// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum SettingsEvent: Equatable, Sendable { case navigate(AppRoute), locked, appearanceChanged(AppearanceMode)
    /// A backup was restored onto this install as a new account; it is unlocked with the code just set.
    case restored(String)
    /// Open the system settings page of this app, where iOS offers the per-app language.
    case openSystemSettings
    /// The app lock of the account was configured (`enabled`); the session follows it at once.
    case appLockChanged(Bool)
    /// The account was removed from this device; the name was read before the call, for the toast.
    case removed(String)
}
