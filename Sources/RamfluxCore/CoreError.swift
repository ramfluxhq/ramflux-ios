// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

public enum CoreErrorCode: Int32, Codable, Sendable {
    case invalidArgument = 1, invalidCanonicalJSON, unsupportedVersion, capabilityRejected
    case authenticationFailed, deviceRevoked, cryptoFailed, storageFailed, transportUnavailable
    case timeout, replayRejected, permissionDenied, mcpGrantRejected, objectTransferFailed
    case rateLimited, internalFailure, panicAborted, accountBusy, objectErased
    case objectIdentityConflict, objectOwnershipUnverified, custodyForkFenced, schemaResetRequired
    case pending, cancelled, closed, resyncRequired
    /// 28 and 29 belong to pairing. The client released its files for the background.
    case suspended = 30
    /// Host custody is locked (before the first device unlock); no client was opened.
    case vaultLocked = 31
}

/// A lost waiter is not proof of no effect. Reconcile using the original operation ID.
public struct CoreFailure: Error, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Effect: String, Codable, Sendable { case none, refused, unknown }
    public let writerReleaseConfirmed: Bool
    public let rawCode: Int32
    public var code: CoreErrorCode? { CoreErrorCode(rawValue: rawCode) }
    public let effect: Effect
    public let operationID: String?
    public let reasonCode: String?
    /// Allowlisted generated error name. Never peer prose.
    public let typedName: String?
    /// The SDK's own status name for the failure (`InvalidArgument`, `Cancelled`, ...), from the completion root.
    /// A token of letters, digits and underscores only; never peer prose.
    public let statusName: String?
    /// The SDK's typed reason from the completion root (`directory_unavailable`, ...); the status name or one of the
    /// SDK's generic tokens when it has nothing finer. Same token alphabet as `statusName`.
    public let reason: String?
    public let response: JSONValue?
    public let sealedResponse: SecretBytes?
    public var debugDescription: String { description }
    public var description: String { "CoreFailure(code: \(rawCode), effect: \(effect.rawValue))" }
    public init(code: Int32, effect: Effect = .unknown, operationID: String? = nil, reasonCode: String? = nil, typedName: String? = nil, statusName: String? = nil, reason: String? = nil, response: JSONValue? = nil, sealedResponse: SecretBytes? = nil, writerReleaseConfirmed: Bool = false) {
        self.writerReleaseConfirmed = writerReleaseConfirmed
        rawCode = code; self.effect = effect; self.operationID = operationID; self.reasonCode = reasonCode; self.typedName = typedName; self.statusName = statusName; self.reason = reason; self.response = response; self.sealedResponse = sealedResponse
    }
    /// The reason when it says more than the status itself: nil for the status name and the SDK's generic tokens
    /// (`invalid_argument`, `internal_error`, `cancelled`), which stand for "no finer reason".
    public var specificReason: String? {
        guard let reason, reason != statusName, !Self.genericReasons.contains(reason) else { return nil }
        return reason
    }
    private static let genericReasons: Set<String> = ["invalid_argument", "internal_error", "cancelled"]
    /// A token as the SDK emits them: 1 to 128 ASCII letters, digits and underscores.
    static func token(_ value: JSONValue?) -> String? {
        guard let text = value?.string, (1...128).contains(text.utf8.count), text.utf8.allSatisfy({ $0 == 95 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return text
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.writerReleaseConfirmed == rhs.writerReleaseConfirmed && lhs.rawCode == rhs.rawCode && lhs.effect == rhs.effect && lhs.operationID == rhs.operationID
            && lhs.reasonCode == rhs.reasonCode && lhs.typedName == rhs.typedName && lhs.statusName == rhs.statusName && lhs.reason == rhs.reason && lhs.response == rhs.response && lhs.sealedResponse === rhs.sealedResponse
    }

}

public enum BridgeError: Error, Sendable, Equatable {
    case closed, invalidInput, invalidResponse, responseTooLarge, incompatibleABI
    case resyncRequired, secretConsumed, invalidCeremonyState, orphanedVault, missingVault
    case keychain(Int32), unsafeStoragePath, lockStillHeld
}
