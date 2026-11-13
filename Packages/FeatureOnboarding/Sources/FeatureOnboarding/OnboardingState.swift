// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public struct OnboardingState: Equatable, Sendable {
    public var stage: OnboardingStage = .welcome
    public var name = ""
    public var address = ""
    public var recoveryAccount = ""
    public var normalized: NodeAddress?
    public var nodes: [NodeRecord] = []
    public var selectedNodeID: String?
    public var expectedNodeKey = ""
    public var candidate: NodeRecord?
    public var busy = false
    public var failure: AppFailure?
    public var metadata: CeremonyMetadata?
    public var displayID: UUID?
    public var positions: [Int] = []
    public var anchorChecked = false
    public var unlockingSavedAccount = false
    public var confirmationConsumed = false
    public var completedAccount: AccountRecord?
    public init(stage: OnboardingStage = .welcome) { self.stage = stage }
}
