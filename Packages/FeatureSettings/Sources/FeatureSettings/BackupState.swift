// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
/// Backup and restore (board MOB-G09). `account` is nil when restoring onto a new install.
public struct BackupState: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case overview
        /// New archive passphrase for a backup; `allowMissingAttachments` after an explicit retry.
        case createPassphrase(allowMissingAttachments: Bool)
        /// Passphrase of the picked archive.
        case importPassphrase(URL)
        /// A new six-digit code for an archive that becomes a new account.
        case installCode(BackupRecord)
        /// Host-drawn confirmation before merging an archive into the existing account.
        case confirmMerge(BackupRecord)
        /// A new-install restore finished; the account is unlocked with the code just set.
        case restored(String)
    }
    public let account: String?
    public var window = RowWindow<BackupRecord>()
    public var step: Step = .overview
    /// The attended subscription is live; the SDK refuses job requests until it is.
    public var attended = false
    public var loading = false
    public var busy = false
    public var failure: AppFailure?
    public var importSelecting = false
    /// The finished backup whose archive is being moved to a place the user picks.
    public var exporting: BackupRecord?
    public init(account: String?) { self.account = account }
}
public enum BackupAction: Equatable, Sendable, CustomStringConvertible {
    case appeared, disappeared, refresh, loadMore
    case startCreate, retryAllowingMissing, submitCreate(SensitiveSubmission)
    case selectImport, importSelected(URL), importFailed, cancelImport, submitVerify(SensitiveSubmission)
    case requestInstall(String), submitInstallCode(SensitiveSubmission), confirmMerge(String)
    case cancelJob(String), export(String), exportFinished(Bool), discard(String), back, finish
    public var description: String { "BackupAction" }
}
