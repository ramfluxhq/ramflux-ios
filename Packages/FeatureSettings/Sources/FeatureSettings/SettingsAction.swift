// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum SettingsAction: Equatable, Sendable, CustomStringConvertible {
    case reconcileOriginal(String)
    case appeared, disappeared, refresh, open(AppRoute), lock, requestRevoke(String), cancelRevoke, confirmRevoke(String)
    case appearance(AppearanceMode), retention(Int64), saveRetention, requestPolicy(autoAccept: Bool), unavailable(SettingsUnavailable)
    case dismissModal, setDefault(String)
    case startChangeCode, submitChangeCode(SensitiveSubmission), cancelChangeCode, openSystemLanguage
    public var description: String { "SettingsAction" }
}
