// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// One pairing ceremony as the SDK names it: the operation id and its generation (`ramflux.pairing.*.v2`).
public struct PairingOperation: Hashable, Sendable {
    public let id: String
    public let generation: UInt64
    public init(id: String, generation: UInt64) { self.id = id; self.generation = generation }
}

/// The ceremony phases of `ramflux.pairing.Update.v2`, in protocol order (`local_dto::PHASES`).
public enum PairingPhase: String, CaseIterable, Sendable {
    case invited, commitments, revealed
    case sasPending = "sas_pending"
    case mutuallyConfirmed = "mutually_confirmed"
    case proposalPending = "proposal_pending"
    case prepared, submitted, acknowledged
    case locallyInstalled = "locally_installed"
    case completed, cancelled, expired, rejected
    public var isTerminal: Bool { [.completed, .cancelled, .expired, .rejected].contains(self) }
    /// The other device has not reached the ceremony yet: the invitation is still the thing to show.
    public var awaitsJoiner: Bool { self == .invited || self == .commitments }
}

/// The inviting device's view of a ceremony (`device.pair.status`, `confirm`, `approve`, `cancel`).
/// Peer facts come from the joining device and are untrusted text; ids are compared identifiers.
public struct PairingProgress: Equatable, Sendable {
    public let operation: PairingOperation
    public let phase: PairingPhase
    public let expiresAt: Date
    public let transcriptHash: String?
    /// The seven SAS emoji indices (0–63) shown on both devices; only in `sas_pending` and `mutually_confirmed`.
    public let emoji: [Int]?
    public let peerDeviceID: String?
    public let peerName: String?
    public let capabilities: [String]
    public let leaseNotBefore: Date
    public let leaseExpiresAt: Date
    public let proposalHash: String?
    /// The SDK result code of a terminal ceremony (`PairingIssue` raw values), or `PublicationPending`.
    public let result: String?
    public init(operation: PairingOperation, phase: PairingPhase, expiresAt: Date, transcriptHash: String? = nil, emoji: [Int]? = nil,
                peerDeviceID: String? = nil, peerName: String? = nil, capabilities: [String] = [], leaseNotBefore: Date = .distantPast,
                leaseExpiresAt: Date = .distantPast, proposalHash: String? = nil, result: String? = nil) {
        self.operation = operation; self.phase = phase; self.expiresAt = expiresAt; self.transcriptHash = transcriptHash; self.emoji = emoji
        self.peerDeviceID = peerDeviceID; self.peerName = peerName; self.capabilities = capabilities; self.leaseNotBefore = leaseNotBefore
        self.leaseExpiresAt = leaseExpiresAt; self.proposalHash = proposalHash; self.result = result
    }
    /// The SAS can be compared: seven indices and the transcript they belong to.
    public var canCompare: Bool { phase == .sasPending && emoji?.count == 7 && transcriptHash != nil }
    /// The joining device's enrolment proposal is ready for this device's decision.
    public var canApprove: Bool { phase == .proposalPending && proposalHash != nil && transcriptHash != nil && peerDeviceID != nil }
}

/// Why a pairing step could not go ahead: the SDK's pairing error codes (`channel::error_code`) plus local checks.
public enum PairingIssue: String, CaseIterable, Equatable, Sendable {
    case busy = "Busy", invalidInput = "InvalidInput", expired = "Expired", retired = "Retired", wrongRole = "WrongRole"
    case wrongContext = "WrongContext", replay = "Replay", headChanged = "HeadChanged", primaryRequired = "PrimaryRequired"
    case sasMismatch = "SasMismatch", publicationPending = "PublicationPending", updateRequired = "UpdateRequired"
    case vaultUnavailable = "VaultUnavailable", notFound = "NotFound"
    case transferCapacity = "TransferCapacity", transferFloorsTooLarge = "TransferFloorsTooLarge"
    /// The device name is empty, longer than 128 bytes or contains control characters (local).
    case deviceName = "local.deviceName"
    /// The invitation does not fit in one QR code (local; the SDK has no shorter form).
    case invitationTooLarge = "local.invitationTooLarge"
    /// The status changed between showing the seven symbols and confirming them (local).
    case comparisonChanged = "local.comparisonChanged"
    /// Any other result the SDK reports.
    case other = "local.other"
    public static func sdk(_ code: String?) -> Self? {
        guard let code, let issue = Self(rawValue: code), !issue.rawValue.hasPrefix("local.") else { return nil }
        return issue
    }
    var messageKey: String {
        switch self {
        case .deviceName: "pairing.failure.deviceName"
        case .invitationTooLarge: "pairing.failure.invitationTooLarge"
        case .comparisonChanged: "pairing.failure.comparisonChanged"
        case .other: "pairing.failure.other"
        default: "pairing.failure." + rawValue
        }
    }
}
