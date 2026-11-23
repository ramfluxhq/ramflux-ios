// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
/// Why a backup or restore step could not go ahead: local pre-checks, SDK refusals (`BackupRefused`
/// `reason_code`, archive passphrase policy codes) and job failure codes (protocol `BackupFailureCode`).
public enum BackupIssue: String, Equatable, Sendable, CaseIterable {
    /// No archive passphrase was entered (local).
    case passphraseEmpty
    /// Fewer than 15 Unicode scalars (SDK `too_short`; pre-checked locally).
    case passphraseTooShort
    /// On the SDK's common-passphrase list (SDK `too_common`).
    case passphraseTooCommon
    /// The repeated archive passphrase differs (local only).
    case passphraseMismatch
    /// The archive passphrase does not open the archive (SDK `wrong_passphrase`).
    case wrongPassphrase
    /// The picked file exceeds the phone's 256 MiB import bound (local).
    case importTooLarge
    /// The SDK only runs backup jobs for an attended frontend: the screen must be open and live.
    case attendanceRequired
    /// The account must be unlocked (SDK `account_locked`).
    case accountLocked
    /// Restoring onto a new install needs a new six-digit account code (SDK `restore_setup_required`).
    case restoreSetupRequired
    case insufficientSpace
    /// The archive is damaged or was changed (`tampered`, `truncated`, `attachment_mismatch`, `identity_rollback`).
    case damaged
    /// The archive needs a newer app (`unsupported_version`, `schema_reset_required`).
    case unsupportedVersion
    case unreadable
    case notWritable
    /// Some attachments are not on this phone (`attachments_unavailable`).
    case attachmentsUnavailable
    /// The job stopped before it finished (`interrupted`, `staging_expired`, `account_busy`).
    case interrupted
    /// The archive conflicts with data on this phone (`root_conflict`, `object_*`).
    case conflict
    /// The account is still waiting for its node (`networking_pending`).
    case networkingPending
    /// The node or account authority refused the installation (`authorization_rejected`).
    case authorizationRejected
    /// Any other SDK code; the job row still shows the state.
    case other
    /// Minimum archive passphrase length in Unicode scalars (`MIN_PASSPHRASE_SCALARS` in the SDK).
    public static let minimumScalars = 15
    /// Maps an SDK failure, refusal or passphrase policy code.
    public static func sdk(_ code: String) -> Self {
        switch code {
        case "too_short": .passphraseTooShort
        case "too_common": .passphraseTooCommon
        case "wrong_passphrase": .wrongPassphrase
        case "account_locked": .accountLocked
        case "restore_setup_required": .restoreSetupRequired
        case "insufficient_space": .insufficientSpace
        case "tampered", "truncated", "attachment_mismatch", "identity_rollback": .damaged
        case "unsupported_version", "schema_reset_required": .unsupportedVersion
        case "unreadable": .unreadable
        case "not_writable": .notWritable
        case "attachments_unavailable": .attachmentsUnavailable
        case "interrupted", "staging_expired", "account_busy", "install_in_progress": .interrupted
        case "root_conflict", "object_identity_conflict", "object_ownership_unverified", "object_erased": .conflict
        case "networking_pending": .networkingPending
        case "authorization_rejected": .authorizationRejected
        default: .other
        }
    }
    var messageKey: String { "backup.failure." + rawValue }
}
