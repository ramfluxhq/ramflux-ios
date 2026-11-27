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
    /// Turns the account's app lock on or off with its timeout (milliseconds); the page reads the SDK's answer back.
    case configureAppLock(enabled: Bool, timeoutMilliseconds: UInt64)
    /// The account-code sheet of a weakening change: submit the code (its one copy is taken) or cancel.
    case submitAccountCode(SensitiveSubmission), cancelAccountCode
    /// `signOut` closes the account on this phone; removal asks for confirmation first.
    case signOut, requestRemoveLocal, confirmRemoveLocal
    /// Username page: open the claim sheet, edit its name, continue to the recovery phrase, submit the phrase, cancel, re-read.
    case startClaimUsername, claimNameChanged(String), continueClaimUsername, submitClaimUsername(SensitiveSubmission), cancelClaimUsername, refreshUsername
    /// The scene leaves `.active`: the claim sheet closes (its phrase field is erased) and a claim in flight is cancelled.
    case conceal
    public var description: String { "SettingsAction" }
}
