// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum OnboardingStage: String, CaseIterable, Identifiable, Sendable {
    case launch, start, connection, address, checkingAddress, verifying, connectionFailed, restoring, offline
    case defaultNode, identity, verificationFailed, saveFailed, configuration, normalizedAddress, saving, saved
    case welcome, create, savePhrase, confirmPhrase, localUnlock, complete, link, recover
    public var id: Self { self }
    public var board: String { "MOB-S" + String(format: "%02d", (Self.allCases.firstIndex(of: self) ?? 0) + 1) }
    public var title: String {
        switch self {
        case .launch: "Ramflux"; case .start, .welcome: "Keep your conversations connected"
        case .connection, .defaultNode: "Choose a node"; case .address: "Custom node"
        case .checkingAddress, .normalizedAddress: "Check the node address"; case .verifying: "Verifying the node"
        case .connectionFailed: "Unable to connect"; case .restoring: "Restoring your connection"; case .offline: "You are offline"
        case .identity: "Check the node identity"; case .verificationFailed: "Node verification failed"; case .saveFailed: "Unable to save this node"
        case .configuration: "Review your connection"; case .saving: "Saving your node"; case .saved: "Node saved"
        case .create: "Create an account"; case .savePhrase: "Save your recovery phrase"; case .confirmPhrase: "Confirm your recovery phrase"
        case .localUnlock: "Set up local unlock"; case .complete: "Account is ready"; case .link: "Link an existing account"; case .recover: "Recover your account"
        }
    }
}
public struct OnboardingState: Equatable, Sendable {
    public var stage: OnboardingStage = .welcome
    public var name = ""
    public var address = ""
    public var recoveryAccount = ""
    public var normalized: NodeAddress?
    public var nodes: [NodeRecord] = []
    public var selectedNodeID: String?
    public var candidate: NodeRecord?
    public var busy = false
    public var failure: AppFailure?
    public var metadata: CeremonyMetadata?
    public var display: RecoveryDisplay?
    public var positions: [Int] = []
    public var anchorChecked = false
    public var unlockingSavedAccount = false
    public var confirmationConsumed = false
    public var completedAccount: AccountRecord?
    public init(stage: OnboardingStage = .welcome) { self.stage = stage }
}
