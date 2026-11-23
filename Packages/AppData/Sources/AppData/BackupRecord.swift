// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
/// One backup or restore job as the SDK reports it (`account.backup.jobs`, protocol `BackupJob`).
public struct BackupRecord: Identifiable, Equatable, Sendable {
    /// Progress of a running job (protocol `BackupProgress`); totals are absent until the SDK knows them.
    public struct Progress: Equatable, Sendable {
        public let category: String
        public let itemsDone: UInt64
        public let itemsTotal: UInt64?
        public let bytesDone: UInt64
        public let bytesTotal: UInt64?
        public init(category: String, itemsDone: UInt64, itemsTotal: UInt64? = nil, bytesDone: UInt64, bytesTotal: UInt64? = nil) {
            self.category = category; self.itemsDone = itemsDone; self.itemsTotal = itemsTotal; self.bytesDone = bytesDone; self.bytesTotal = bytesTotal
        }
    }
    /// Why a job failed (protocol `BackupFailure`); `code` is the SDK's snake_case failure code.
    public struct Failure: Equatable, Sendable {
        public let code: String
        public let retryable: Bool
        public let neededBytes: UInt64?
        public let availableBytes: UInt64?
        public let unavailableCount: UInt64?
        public init(code: String, retryable: Bool = false, neededBytes: UInt64? = nil, availableBytes: UInt64? = nil, unavailableCount: UInt64? = nil) {
            self.code = code; self.retryable = retryable; self.neededBytes = neededBytes; self.availableBytes = availableBytes; self.unavailableCount = unavailableCount
        }
    }
    public static let runningStates: Set<String> = ["preparing", "writing", "verifying", "installing"]
    public static let terminalStates: Set<String> = ["done", "failed", "cancelled"]
    public let id: String
    public let kind: String
    public let state: String
    public let sequence: UInt64
    /// Local account the archive restores into (an existing account when `merge` is true).
    public let accountID: String?
    public let merge: Bool?
    public let shareURL: URL?
    public let progress: Progress?
    public let failure: Failure?
    /// Peer-independent but user-chosen text from the archive; render it as untrusted text.
    public let accountLabel: String?
    /// Unix seconds when the archive was written.
    public let archiveCreatedAt: UInt64?
    public let archiveBytes: UInt64?
    /// The account an installation created or merged into, once the job is done.
    public let installedAccountID: String?
    public var isRunning: Bool { Self.runningStates.contains(state) }
    public var isTerminal: Bool { Self.terminalStates.contains(state) }
    public init(id: String, kind: String, state: String, sequence: UInt64, accountID: String? = nil, merge: Bool? = nil, shareURL: URL? = nil,
                progress: Progress? = nil, failure: Failure? = nil, accountLabel: String? = nil, archiveCreatedAt: UInt64? = nil,
                archiveBytes: UInt64? = nil, installedAccountID: String? = nil) {
        self.id = id; self.kind = kind; self.state = state; self.sequence = sequence; self.accountID = accountID; self.merge = merge; self.shareURL = shareURL
        self.progress = progress; self.failure = failure; self.accountLabel = accountLabel; self.archiveCreatedAt = archiveCreatedAt
        self.archiveBytes = archiveBytes; self.installedAccountID = installedAccountID
    }
}
