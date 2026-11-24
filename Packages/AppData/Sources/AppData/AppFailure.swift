// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum AppFailure: Error, Sendable, Equatable {
    case nodeRequired, nodeKeyMismatch, vaultPermission, vaultLocked, vaultMissing, vaultCorrupt, vaultBusy, vaultUnavailable
    case sdkRefusal(Int32), onboardingProtocol, localStorage, localFailure
    case sdkUnavailable, unsupported, offline, locked, busy, upgradeRequired, invalidData, invalidInput, resyncRequired
    case unavailableResource(String), notAvailable(String), outcomeUnknown, failed, typedRefusal(String)
    case accountCode(AccountCodeIssue)
    /// Too many wrong account codes; the SDK names the wait (`retry_after_ms`), in whole seconds here.
    case accountCodeWait(seconds: Int)
    case backup(BackupIssue)
    case pairing(PairingIssue)
    public var title: String { title(locale: .current) }
    public func title(locale: Locale) -> String {
        switch self {
        case .sdkRefusal, .localStorage, .localFailure: AppDataStrings.text("request.refusal.title", locale: locale)
        case .nodeRequired, .nodeKeyMismatch, .vaultPermission, .vaultLocked, .vaultMissing, .vaultCorrupt, .vaultBusy, .vaultUnavailable, .onboardingProtocol:
            AppDataStrings.text("onboarding.refusal.title", locale: locale)
        case .sdkUnavailable: AppDataStrings.text("failure.sdkUnavailable.title", locale: locale)
        case .unsupported, .notAvailable, .unavailableResource: AppDataStrings.text("failure.unavailable.title", locale: locale)
        case .offline: AppDataStrings.text("common.connection.failed", locale: locale)
        case .locked: AppDataStrings.text("failure.locked.title", locale: locale)
        case .busy: AppDataStrings.text("failure.busy.title", locale: locale)
        case .upgradeRequired: AppDataStrings.text("failure.upgradeRequired.title", locale: locale)
        case .resyncRequired: AppDataStrings.text("failure.resyncRequired.title", locale: locale)
        case .invalidData: AppDataStrings.text("failure.invalidData.title", locale: locale)
        case .invalidInput: AppDataStrings.text("failure.invalidInput.title", locale: locale)
        case .outcomeUnknown: AppDataStrings.text("failure.outcomeUnknown.title", locale: locale)
        case .failed: AppDataStrings.text("request.refusal.title", locale: locale)
        case .typedRefusal(let name): AppDataStrings.text(Self.refusalTitle(name), locale: locale)
        case .accountCode, .accountCodeWait: AppDataStrings.text("accountCode.failure.title", locale: locale)
        case .backup: AppDataStrings.text("backup.failure.title", locale: locale)
        case .pairing: AppDataStrings.text("pairing.failure.title", locale: locale)
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
        case .sdkUnavailable: AppDataStrings.text("failure.sdkUnavailable.message", locale: locale)
        case .unsupported: AppDataStrings.text("failure.unsupported.message", locale: locale)
        case .offline: AppDataStrings.text("failure.offline.message", locale: locale)
        case .locked: AppDataStrings.text("failure.locked.message", locale: locale)
        case .busy: AppDataStrings.text("failure.busy.message", locale: locale)
        case .upgradeRequired: AppDataStrings.text("failure.upgradeRequired.message", locale: locale)
        case .resyncRequired: AppDataStrings.text("failure.resyncRequired.message", locale: locale)
        case .invalidData: AppDataStrings.text("failure.invalidData.message", locale: locale)
        case .invalidInput: AppDataStrings.text("failure.invalidInput.message", locale: locale)
        case .unavailableResource(let key): AppDataStrings.text(key, locale: locale)
        case .notAvailable(let message): message
        case .outcomeUnknown: AppDataStrings.text("failure.outcomeUnknown.message", locale: locale)
        case .failed: AppDataStrings.text("request.localFailure", locale: locale)
        case .typedRefusal(let name): AppDataStrings.text(Self.refusalMessage(name), locale: locale)
        case .accountCode(let issue): AppDataStrings.text(Self.accountCodeMessage(issue), locale: locale)
        case .accountCodeWait(let seconds):
            AppDataStrings.format("accountCode.failure.wait", Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale)), locale: locale)
        case .backup(let issue): AppDataStrings.text(issue.messageKey, locale: locale)
        case .pairing(let issue): AppDataStrings.text(issue.messageKey, locale: locale)
        }
    }
    /// A refusal of the typed account code itself (wrong, malformed, retry later), not of the account.
    public var isAccountCodeEntry: Bool {
        if case .accountCode = self { return true }
        if case .accountCodeWait = self { return true }
        return self == .invalidInput || self == .busy
    }
    public var canRetry: Bool {
        if case .typedRefusal = self { return false }
        if case .accountCode(let issue) = self { return issue != .attemptsExhausted && issue != .deviceUnlockUnavailable }
        return self != .outcomeUnknown && self != .sdkUnavailable && self != .unsupported
    }
    /// A username directory call: the directory's typed refusals (`username_directory` codes) become an
    /// honest unavailable state; anything else maps as usual.
    public static func mapUsername(_ error: any Error) -> Self {
        guard let failure = error as? CoreFailure else { return map(error) }
        switch failure.reasonCode ?? failure.response?["error"]?["code"]?.string {
        case "directory_unavailable": return .unavailableResource("username.unavailable.directory")
        case "name_not_found", "not_found": return .unavailableResource("username.unavailable.notFound")
        // A directory refusal without a typed reason (the pinned SDK answers internal, code 16) is still a
        // refusal of the directory, not an unknown outcome: nothing was claimed or added.
        default: return failure.code == .internalFailure ? .unavailableResource("username.unavailable.refused") : map(error)
        }
    }
    public static func map(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? CoreFailure {
            if let name = failure.typedName, let refusal = Self.knownRefusal(name) { return refusal }
            if let issue = AccountCodeIssue.sdk(failure.reasonCode) {
                if issue == .retryLater, let wait = Self.retryAfterMilliseconds(failure) { return .accountCodeWait(seconds: Int((wait + 999) / 1000)) }
                return .accountCode(issue)
            }
            // A definite refusal named by its reason, whatever effect the bridge reports.
            if let reason = failure.reasonCode, reason == "already_contact" { return .typedRefusal(reason) }
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
            case .vaultLocked: return .vaultLocked
            case .suspended: return .offline
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
    /// The SDK's wait before the next attempt, from the public error frame or the sealed error completion.
    private static func retryAfterMilliseconds(_ failure: CoreFailure) -> UInt64? {
        func wait(_ frame: JSONValue?) -> UInt64? {
            guard let value = frame?["error"]?["retry_after_ms"] ?? frame?["response"]?["error"]?["retry_after_ms"] else { return nil }
            switch value { case .unsigned(let ms): return ms; case .number(let ms): return ms >= 0 && ms < 1e15 ? UInt64(ms) : nil; default: return nil }
        }
        if let ms = wait(failure.response) { return ms }
        guard let sealed = failure.sealedResponse, let frame = try? sealed.consume({ try JSONDecoder().decode(JSONValue.self, from: Data($0)) }) else { return nil }
        return wait(frame)
    }
    private static func accountCodeMessage(_ issue: AccountCodeIssue) -> String {
        switch issue {
        case .notSixDigits: "accountCode.failure.notSixDigits"
        case .trivial: "accountCode.failure.trivial"
        case .mismatch: "accountCode.failure.mismatch"
        case .retryLater: "accountCode.failure.retryLater"
        case .attemptsExhausted: "accountCode.failure.attemptsExhausted"
        case .required: "accountCode.failure.required"
        case .deviceUnlockUnavailable: "accountCode.failure.deviceUnlockUnavailable"
        }
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
        case "already_contact": "refusal.already_contact.title"
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
        case "already_contact": "refusal.already_contact"
        default: "request.localFailure"
        }
    }
}
