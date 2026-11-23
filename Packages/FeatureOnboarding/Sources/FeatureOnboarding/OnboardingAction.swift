// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum OnboardingAction: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case appeared, disappeared, conceal, cancel, expired
    case create, recover, restoreBackup, link, customNode, nameChanged(String), addressChanged(String), recoveryAccountChanged(String), nodeSelected(String), expectedNodeKeyChanged(String)
    case checkAddress, inspectOrigin, reviewNodeKey, saveNode, setDefault, beginCreation, showPhrase, hidePhrase, beginRecovery, checkAnchor(Bool)
    case unlockExisting, continueUnlock, submit(SensitiveSubmission), done
    /// Get started (MOB-S02) continues to the account choice (MOB-S18).
    case getStarted
    /// Continue with an existing identity on this phone (MOB-A01).
    case existingAccount
    /// Shows or hides the device unlock information (MOB-A07).
    case unlockInfo(Bool)
    public var description: String { switch self { case .submit: "submit"; default: "OnboardingAction" } }
    public var debugDescription: String { description }
}
