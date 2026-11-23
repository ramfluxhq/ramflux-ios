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
    /// The device unlock information (MOB-A07) is shown over the current step.
    public var showingUnlockInfo = false
    public init(stage: OnboardingStage = .connection) { self.stage = stage }
}
