// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum AppFailure: Error, Sendable, Equatable {
    case nodeRequired, nodeKeyMismatch, vaultPermission, vaultLocked, vaultMissing, vaultCorrupt, vaultBusy, vaultUnavailable
    case sdkRefusal(Int32), onboardingProtocol, localStorage, localFailure
    case sdkUnavailable, unsupported, offline, locked, busy, upgradeRequired, invalidData, invalidInput, resyncRequired
    case unavailableResource(String), notAvailable(String), outcomeUnknown, failed, typedRefusal(String)
    public var title: String { title(locale: .current) }
    public func title(locale: Locale) -> String {
        switch self {
        case .sdkRefusal, .localStorage, .localFailure: AppDataStrings.text("request.refusal.title", locale: locale)
        case .nodeRequired, .nodeKeyMismatch, .vaultPermission, .vaultLocked, .vaultMissing, .vaultCorrupt, .vaultBusy, .vaultUnavailable, .onboardingProtocol:
            AppDataStrings.text("onboarding.refusal.title", locale: locale)
        case .sdkUnavailable: AppDataStrings.text("copy.5562fbd3e629", locale: locale)
        case .unsupported, .notAvailable, .unavailableResource: AppDataStrings.text("copy.787406ddea2a", locale: locale)
        case .offline: AppDataStrings.text("copy.e40966162b11", locale: locale)
        case .locked: AppDataStrings.text("copy.68d02ee6497e", locale: locale)
        case .busy: AppDataStrings.text("copy.9dcdd3257d89", locale: locale)
        case .upgradeRequired: AppDataStrings.text("copy.5856eb3d60b0", locale: locale)
        case .resyncRequired: AppDataStrings.text("copy.9503c0e50707", locale: locale)
        case .invalidData: AppDataStrings.text("copy.536ec5ca4da6", locale: locale)
        case .invalidInput: AppDataStrings.text("copy.29ea6afd1a52", locale: locale)
        case .outcomeUnknown: AppDataStrings.text("copy.b5e82d852d43", locale: locale)
        case .failed: AppDataStrings.text("request.refusal.title", locale: locale)
        case .typedRefusal(let name): AppDataStrings.text(Self.refusalTitle(name), locale: locale)
        }
    }
    public var message: String { message(locale: .current) }
    public func message(locale: Locale) -> String {
        switch self {
        case .nodeRequired: AppDataStrings.text("onboarding.nodeRequired", locale: locale)
        case .nodeKeyMismatch: AppDataStrings.text("onboarding.nodeKeyMismatch", locale: locale)
        case .vaultPermission: AppDataStrings.text("onboarding.vaultPermission", locale: locale)
        case .vaultLocked: AppDataStrings.text("onboarding.vaultLocked", locale: locale)
        case .vaultMissing: AppDataStrings.text("onboarding.vaultMissing", locale: locale)
        case .vaultCorrupt: AppDataStrings.text("onboarding.vaultCorrupt", locale: locale)
        case .vaultBusy: AppDataStrings.text("onboarding.vaultBusy", locale: locale)
        case .vaultUnavailable: AppDataStrings.text("onboarding.vaultUnavailable", locale: locale)
        case .sdkRefusal(let code): AppDataStrings.format("onboarding.sdkRefusal", String(code), locale: locale)
        case .onboardingProtocol: AppDataStrings.text("onboarding.protocol", locale: locale)
        case .localStorage: AppDataStrings.text("request.localStorage", locale: locale)
        case .localFailure: AppDataStrings.text("request.localFailure", locale: locale)
        case .sdkUnavailable: AppDataStrings.text("copy.c3654c6a066c", locale: locale)
        case .unsupported: AppDataStrings.text("copy.a18c44969ead", locale: locale)
        case .offline: AppDataStrings.text("copy.c294a0b00e74", locale: locale)
        case .locked: AppDataStrings.text("copy.70de3acff368", locale: locale)
        case .busy: AppDataStrings.text("copy.dafb5d4bae01", locale: locale)
        case .upgradeRequired: AppDataStrings.text("copy.f92268007794", locale: locale)
        case .resyncRequired: AppDataStrings.text("copy.dcaee1a8b499", locale: locale)
        case .invalidData: AppDataStrings.text("copy.7fe3baa7c52d", locale: locale)
        case .invalidInput: AppDataStrings.text("copy.84f9c932bfcd", locale: locale)
        case .unavailableResource(let key): AppDataStrings.text(key, locale: locale)
        case .notAvailable(let message): message
        case .outcomeUnknown: AppDataStrings.text("copy.1b6fe0889add", locale: locale)
        case .failed: AppDataStrings.text("request.localFailure", locale: locale)
        case .typedRefusal(let name): AppDataStrings.text(Self.refusalMessage(name), locale: locale)
        }
    }
    public var canRetry: Bool {
        if case .typedRefusal = self { return false }
        return self != .outcomeUnknown && self != .sdkUnavailable && self != .unsupported
    }
    public static func map(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? CoreFailure {
            if let name = failure.typedName, let refusal = Self.knownRefusal(name) { return refusal }
            if failure.effect == .unknown, failure.operationID != nil { return .outcomeUnknown }
            switch failure.reasonCode {
            case "vault_permission": return .vaultPermission
            case "vault_locked": return .vaultLocked
            case "vault_missing": return .vaultMissing
            case "vault_corrupt": return .vaultCorrupt
            case "vault_busy": return .vaultBusy
            case "vault_primary_unavailable": return .vaultUnavailable
            default: break
            }
            switch failure.code {
            case .unsupportedVersion, .schemaResetRequired: return .upgradeRequired
            case .authenticationFailed, .deviceRevoked, .permissionDenied, .custodyForkFenced: return .locked
            case .accountBusy, .rateLimited: return .busy
            case .transportUnavailable, .timeout, .closed: return .offline
            case .invalidArgument, .invalidCanonicalJSON: return .invalidInput
            default: return .sdkRefusal(failure.rawCode)
            }
        }
        if let bridge = error as? BridgeError {
            switch bridge {
            case .resyncRequired: return .resyncRequired
            case .closed: return .offline
            case .invalidInput: return .invalidInput
            case .incompatibleABI: return .upgradeRequired
            case .missingVault: return .vaultMissing
            case .orphanedVault: return .vaultCorrupt
            case .keychain(let code): return code == -34018 ? .vaultPermission : .vaultUnavailable
            case .unsafeStoragePath: return .localStorage
            case .lockStillHeld: return .busy
            default: return .invalidData
            }
        }
        if error is UnavailableCapability { return .unsupported }
        if error is DecodingError { return .invalidData }
        if error is URLError { return .offline }
        let native = error as NSError
        if native.domain == NSCocoaErrorDomain { return .localStorage }
        if error is BridgeError { return .invalidData }
        return .localFailure
    }
    private static func knownRefusal(_ name: String) -> AppFailure? {
        switch name {
        case "invalid_argument", "invalid_json", "peer_upgrade_required", "storage_capacity", "schema_reset_required", "resync_required", "edit_conflict", "not_authorized", "target_not_found", "target_deleted", "payload_too_large", "rate_limited", "ephemeral_unavailable", "crypto_failure", "not_connected", "internal":
            return .typedRefusal(name)
        default: return nil
        }
    }
    private static func refusalTitle(_ name: String) -> String {
        switch name {
        case "invalid_argument": "refusal.invalid_argument.title"
        case "invalid_json": "refusal.invalid_json.title"
        case "peer_upgrade_required": "refusal.peer_upgrade_required.title"
        case "storage_capacity": "refusal.storage_capacity.title"
        case "schema_reset_required": "refusal.schema_reset_required.title"
        case "resync_required": "refusal.resync_required.title"
        case "edit_conflict": "refusal.edit_conflict.title"
        case "not_authorized": "refusal.not_authorized.title"
        case "target_not_found": "refusal.target_not_found.title"
        case "target_deleted": "refusal.target_deleted.title"
        case "payload_too_large": "refusal.payload_too_large.title"
        case "rate_limited": "refusal.rate_limited.title"
        case "ephemeral_unavailable": "refusal.ephemeral_unavailable.title"
        case "crypto_failure": "refusal.crypto_failure.title"
        case "not_connected": "refusal.not_connected.title"
        case "internal": "refusal.internal.title"
        default: "request.refusal.title"
        }
    }
    private static func refusalMessage(_ name: String) -> String {
        switch name {
        case "invalid_argument": "refusal.invalid_argument"
        case "invalid_json": "refusal.invalid_json"
        case "peer_upgrade_required": "refusal.peer_upgrade_required"
        case "storage_capacity": "refusal.storage_capacity"
        case "schema_reset_required": "refusal.schema_reset_required"
        case "resync_required": "refusal.resync_required"
        case "edit_conflict": "refusal.edit_conflict"
        case "not_authorized": "refusal.not_authorized"
        case "target_not_found": "refusal.target_not_found"
        case "target_deleted": "refusal.target_deleted"
        case "payload_too_large": "refusal.payload_too_large"
        case "rate_limited": "refusal.rate_limited"
        case "ephemeral_unavailable": "refusal.ephemeral_unavailable"
        case "crypto_failure": "refusal.crypto_failure"
        case "not_connected": "refusal.not_connected"
        case "internal": "refusal.internal"
        default: "request.localFailure"
        }
    }
}
