// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RamfluxCore
public enum AppFailure: Error, Sendable, Equatable {
    case sdkUnavailable, unsupported, offline, locked, busy, upgradeRequired, invalidData, invalidInput, resyncRequired
    case notAvailable(String), outcomeUnknown, failed
    public var title: String {
        switch self {
        case .sdkUnavailable: "Account services are unavailable"
        case .unsupported, .notAvailable: "Not available yet"
        case .offline: "Unable to connect"
        case .locked: "Unlock this account"
        case .busy: "Please try again shortly"
        case .upgradeRequired: "An update is required"
        case .resyncRequired: "Refresh your local records"
        case .invalidData: "Unable to read this information"
        case .invalidInput: "Check your input"
        case .outcomeUnknown: "Outcome not confirmed"
        case .failed: "Something went wrong"
        }
    }
    public var message: String {
        switch self {
        case .sdkUnavailable: "This build cannot open the account service. Your saved data has not been changed."
        case .unsupported: "This action is not supported by the account service."
        case .offline: "Check your connection. Your local records and drafts are kept."
        case .locked: "Unlock this device before opening your local records."
        case .busy: "Another operation or account writer is still active."
        case .upgradeRequired: "Update Ramflux before continuing with this account."
        case .resyncRequired: "An update gap occurred. Refresh to load current records and reopen updates."
        case .invalidData: "The service returned information this app cannot display."
        case .invalidInput: "Complete the required fields before continuing."
        case .notAvailable(let message): message
        case .outcomeUnknown: "The action may have completed. Check its current status before starting another attempt."
        case .failed: "Your last confirmed state is preserved."
        }
    }
    public var canRetry: Bool { self != .outcomeUnknown && self != .sdkUnavailable && self != .unsupported }
    public static func map(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? CoreFailure {
            if failure.effect == .unknown, failure.operationID != nil { return .outcomeUnknown }
            switch failure.code {
            case .unsupportedVersion, .schemaResetRequired: return .upgradeRequired
            case .authenticationFailed, .deviceRevoked, .permissionDenied, .custodyForkFenced: return .locked
            case .accountBusy, .rateLimited: return .busy
            case .transportUnavailable, .timeout, .closed: return .offline
            case .invalidArgument, .invalidCanonicalJSON: return .invalidInput
            default: return .failed
            }
        }
        if (error as? BridgeError) == .resyncRequired { return .resyncRequired }
        if error is UnavailableCapability { return .unsupported }
        return .failed
    }
}
