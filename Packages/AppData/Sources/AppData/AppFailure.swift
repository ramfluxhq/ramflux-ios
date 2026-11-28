// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum AppFailure: Error, Sendable, Equatable {
    case nodeRequired, nodeKeyMismatch, vaultPermission, vaultLocked, vaultMissing, vaultCorrupt, vaultBusy, vaultUnavailable
    case sdkRefusal(Int32), onboardingProtocol, localStorage, localFailure
    case sdkUnavailable, unsupported, offline, locked, busy, upgradeRequired, invalidData, invalidInput, resyncRequired
    case unavailableResource(String), notAvailable(String), outcomeUnknown, failed, typedRefusal(String)
    /// A refusal the SDK named with a typed reason that has no screen of its own (a token of letters, digits and underscores).
    case sdkReason(String)
    case accountCode(AccountCodeIssue)
    /// The recovery phrase is not the account's (`CustodyConfirmationFailed`); no counter changed.
    case recoveryPhraseMismatch
    /// The recovery ceremony ran out before it was confirmed (`CustodyExpired`).
    case recoveryExpired
    /// Too many wrong account codes; the SDK names the wait (`retry_after_ms`), in whole seconds here.
    case accountCodeWait(seconds: Int, until: ContinuousClock.Instant)
    /// The username directory is rate limiting or at capacity; it names the wait in whole seconds (`retry_after_ms`).
    case usernameRetry(seconds: Int)
    case backup(BackupIssue)
    case pairing(PairingIssue)
    /// A send was refused because the contact's changed identity is not accepted yet (`identity_change_pending`); the
    /// payload is the contact the SDK named. Nothing was sent and nothing is retried on its own.
    case identityChangePending(String)
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
        case .failed, .sdkReason: AppDataStrings.text("request.refusal.title", locale: locale)
        case .typedRefusal(let name): AppDataStrings.text(Self.refusalTitle(name), locale: locale)
        case .accountCode, .accountCodeWait: AppDataStrings.text("accountCode.failure.title", locale: locale)
        case .recoveryPhraseMismatch, .recoveryExpired: AppDataStrings.text("recovery.failure.title", locale: locale)
        case .usernameRetry: AppDataStrings.text("failure.unavailable.title", locale: locale)
        case .backup: AppDataStrings.text("backup.failure.title", locale: locale)
        case .pairing: AppDataStrings.text("pairing.failure.title", locale: locale)
        case .identityChangePending: AppDataStrings.text("refusal.identity_change_pending.title", locale: locale)
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
        case .sdkReason(let reason): AppDataStrings.format("refusal.sdkReason", reason.replacingOccurrences(of: "_", with: " "), locale: locale)
        case .typedRefusal(let name): AppDataStrings.text(Self.refusalMessage(name), locale: locale)
        case .accountCode(let issue): AppDataStrings.text(Self.accountCodeMessage(issue), locale: locale)
        case .recoveryPhraseMismatch: AppDataStrings.text("recovery.failure.phraseMismatch", locale: locale)
        case .recoveryExpired: AppDataStrings.text("recovery.failure.expired", locale: locale)
        case .accountCodeWait(let seconds, _):
            AppDataStrings.format("accountCode.failure.wait", Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale)), locale: locale)
        case .usernameRetry(let seconds): AppDataStrings.format("username.retryIn", String(seconds), locale: locale)
        case .backup(let issue): AppDataStrings.text(issue.messageKey, locale: locale)
        case .pairing(let issue): AppDataStrings.text(issue.messageKey, locale: locale)
        case .identityChangePending: AppDataStrings.text("refusal.identity_change_pending", locale: locale)
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
        if case .sdkReason = self { return false }
        if case .identityChangePending = self { return false }
        if case .accountCode(let issue) = self { return issue != .attemptsExhausted && issue != .deviceUnlockUnavailable }
        return self != .outcomeUnknown && self != .sdkUnavailable && self != .unsupported
    }
    /// A username directory call: the directory's typed refusals (`username_directory` codes) become an
    /// honest unavailable state; anything else maps as usual.
    public static func mapUsername(_ error: any Error) -> Self {
        guard let failure = error as? CoreFailure else { return map(error) }
        switch failure.reasonCode ?? failure.reason ?? failure.response?["error"]?["code"]?.string {
        case "directory_unavailable": return .unavailableResource("username.unavailable.directory")
        case "name_not_found", "not_found": return .unavailableResource("username.unavailable.notFound")
        case "authentication_required", "signature_invalid": return .unavailableResource("username.claim.phraseMismatch")
        case "invalid_username": return .unavailableResource("username.claim.invalid")
        case "username_taken": return .unavailableResource("username.claim.taken")
        case "rate_limited", "capacity":
            let retry = milliseconds(failure.response?["error"]?["retry_after_ms"]) ?? milliseconds(failure.response?["retry_after_ms"])
            return retry.map { .usernameRetry(seconds: max(1, Int((Double($0) / 1000).rounded(.up)))) } ?? .unavailableResource("username.unavailable.retry")
        // Any other typed reason is shown as the SDK named it (`map` does that for codes 1, 16 and 25).
        default: return map(error)
        }
    }
    private static func milliseconds(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number)?: number >= 0 ? number : nil
        case .unsigned(let number)?: Double(number)
        default: nil
        }
    }
    /// A refusal of `account.recover.begin` or `account.recover.confirm` that the SDK named by its reason token; nil for
    /// anything else, which leaves the outcome of a confirmation unknown. The ceremony is consumed by every `confirm`.
    public static func recoveryRefusal(_ error: any Error) -> Self? {
        guard let failure = error as? CoreFailure, let reason = failure.reasonCode else { return nil }
        switch reason {
        case "CustodyConfirmationFailed": return .recoveryPhraseMismatch
        case "CustodyExpired": return .recoveryExpired
        // A header or operation id the client should never have sent: a programming error, shown as the generic failure.
        case "CustodySetupInvalid", "CustodyConfirmRejected", "operation_id", "app_locked": return .onboardingProtocol
        case "wrong_passphrase", "unlock_retry_later", "unlock_attempts_exhausted": return map(error)
        default: return nil
        }
    }
    /// The SDK refused the call because the account's app lock is engaged (`reason_code` `app_locked`). The
    /// caller must cover the records and ask for the account code, never show a generic failure.
    public static func isAppLocked(_ error: any Error) -> Bool {
        guard let failure = error as? CoreFailure else { return false }
        return failure.reasonCode == "app_locked" || failure.reason == "app_locked"
    }
    public static func map(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? CoreFailure {
            if let block = ContactIdentityParsing.sendBlock(failure) { return .identityChangePending(block.contact) }
            if let name = failure.typedName, let refusal = Self.knownRefusal(name) { return refusal }
            if let issue = AccountCodeIssue.sdk(failure.reasonCode) {
                // The wait is the SDK's `retry_after_ms`. A throttle that names no wait is shown without a countdown;
                // the caller reads the wait from the account's app-lock state.
                if issue == .retryLater, let wait = Self.retryAfterMilliseconds(failure) {
                    return .accountCodeWait(seconds: Int((wait + 999) / 1000), until: ContinuousClock.now.advanced(by: .milliseconds(Int(min(wait, 86_400_000)))))
                }
                return .accountCode(issue)
            }
            // A definite refusal named by its reason, whatever effect the bridge reports.
            if let reason = failure.reasonCode, reason == "already_contact" { return .typedRefusal(reason) }
            // Codes 1, 16 and 25 now carry the SDK's typed reason. A named reason is a definite refusal, whatever
            // effect the bridge reports; without one the code keeps its usual mapping below.
            if let reason = failure.specificReason, !reason.hasPrefix("vault_"), [.invalidArgument, .internalFailure, .cancelled].contains(failure.code) { return .sdkReason(reason) }
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
        case .wrong: "accountCode.failure.wrong"
        case .reauthRequired: "accountCode.failure.reauthRequired"
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
        case "card_limit_exceeded": "refusal.card_limit_exceeded.title"
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
        case "card_limit_exceeded": "refusal.card_limit_exceeded"
        default: "request.localFailure"
        }
    }
}
