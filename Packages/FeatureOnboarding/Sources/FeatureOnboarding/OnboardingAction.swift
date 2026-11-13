// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum OnboardingAction: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case appeared, disappeared, conceal, cancel, expired
    case create, recover, link, customNode, nameChanged(String), addressChanged(String), recoveryAccountChanged(String), nodeSelected(String), expectedNodeKeyChanged(String)
    case checkAddress, inspectOrigin, saveNode, setDefault, beginCreation, showPhrase, hidePhrase, beginRecovery, checkAnchor(Bool)
    case unlockExisting, continueUnlock, submit(SensitiveSubmission), done
    public var description: String { switch self { case .submit: "submit"; default: "OnboardingAction" } }
    public var debugDescription: String { description }
}
