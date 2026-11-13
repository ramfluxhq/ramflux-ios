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
}

/// A lost waiter is not proof of no effect. Reconcile using the original operation ID.
public struct CoreFailure: Error, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Effect: String, Codable, Sendable { case none, refused, unknown }
    public let rawCode: Int32
    public var code: CoreErrorCode? { CoreErrorCode(rawValue: rawCode) }
    public let effect: Effect
    public let operationID: String?
    public let reasonCode: String?
    public let response: JSONValue?
    public var debugDescription: String { description }
    public var description: String { "CoreFailure(code: \(rawCode), effect: \(effect.rawValue))" }
    public init(code: Int32, effect: Effect = .unknown, operationID: String? = nil, reasonCode: String? = nil, response: JSONValue? = nil) {
        rawCode = code; self.effect = effect; self.operationID = operationID; self.reasonCode = reasonCode; self.response = response
    }
}

public enum BridgeError: Error, Sendable, Equatable {
    case closed, invalidInput, invalidResponse, responseTooLarge, incompatibleABI
    case resyncRequired, secretConsumed, invalidCeremonyState, orphanedVault, missingVault
    case keychain(Int32), unsafeStoragePath, lockStillHeld
}
