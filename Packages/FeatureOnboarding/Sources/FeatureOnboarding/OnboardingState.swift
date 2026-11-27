// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public struct OnboardingState: Equatable, Sendable {
    public var stage: OnboardingStage = .connection
    public var name = ""
    public var address = ""
    public var recoveryAccount = ""
    public var normalized: NodeAddress?
    public var nodes: [NodeRecord] = []
    public var selectedNodeID: String?
    public var expectedNodeKey = ""
    public var candidate: NodeRecord?
    public var visibleNodeFingerprint: String? { reviewedNode == candidate && canReviewFingerprint ? candidate?.fingerprint : nil }
    public var reviewedNode: NodeRecord?
    public var canReviewFingerprint: Bool { candidate?.publicKey != nil && !expectedNodeKey.isEmpty && expectedNodeKey == candidate?.publicKey }
    public var busy = false
    public var failure: AppFailure?
    public var metadata: CeremonyMetadata?
    public var displayID: UUID?
    public var positions: [Int] = []
    public var anchorChecked = false
    public var unlockingSavedAccount = false
    public var creatingAccount = false
    public var confirmationConsumed = false
    public var completedAccount: AccountRecord?
    /// The completion step is following the SDK's networking state until it reports live.
    public var watchingNetwork = false
    /// The device unlock information (MOB-A07) is shown over the current step.
    public var showingUnlockInfo = false
    /// The display name of an account held on this phone being unlocked (from `account.list`); the unlock step
    /// then shows this name instead of the account id field.
    public var knownAccountName: String?
    /// The confirmation for removing that account from this phone (`account.remove_local`) is shown.
    public var confirmingForget = false
    /// The recovery of the locked account is shown inside the app lock cover: `recoveryAccount` is that account and
    /// cannot change, and the flow offers no other onboarding entry (no backup restore, no account picker).
    public var recoversLockedAccount = false
    public init(stage: OnboardingStage = .connection) { self.stage = stage }
    /// The unlock step for an account this device knows: it asks only for the account code.
    public static func unlockKnown(account: String, name: String) -> OnboardingState {
        var state = OnboardingState(stage: .localUnlock)
        state.unlockingSavedAccount = true; state.recoveryAccount = account; state.knownAccountName = name
        return state
    }
    /// The recovery step for the locked account `account`, bound to that account only.
    public static func recoverLockedAccount(_ account: String) -> OnboardingState {
        var state = OnboardingState(stage: .recover)
        state.recoveryAccount = account; state.recoversLockedAccount = true
        return state
    }
}
