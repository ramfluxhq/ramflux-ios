// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
/// Backup and restore jobs (`account.backup.create/jobs/cancel`, `account.restore.verify/install`).
///
/// The SDK runs these jobs in process for an attended frontend only (`bus/backup_jobs/routing.rs`): the
/// connection must hold a subscription opened with `attended_frontend`. With an account that is the shared
/// account subscription (`observe(account:)`); without one (restoring onto a new install) it is the
/// daemon-scoped job stream (`NativeUpdateSource.observeBackupJobs()`). Callers keep the observation live
/// while they start, cancel or install a job. `account` is nil only for a new install.
public protocol BackupRepository: Sendable {
    /// Jobs of `account`, plus jobs this app session started; with no account, only the latter.
    func jobs(account: String?) async -> RepositoryResult<[BackupRecord]>
    /// The same jobs, newest first, behind the paged row interface (`account.backup.jobs` is unpaged).
    func jobsPage(account: String?, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<BackupRecord>>
    /// The attended subscription that admits job requests and reports job changes.
    func observe(account: String?) async -> RepositoryObservation
    /// Writes an archive into private storage, sealed with a new archive passphrase (`passphrase`).
    func create(account: String, credentials: SensitiveSubmission, allowMissingAttachments: Bool, operationID: String) async -> RepositoryResult<BackupRecord>
    /// Copies the picked archive into private storage (at most 256 MiB) and verifies it with its passphrase.
    func verify(account: String?, source: URL, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord>
    /// Installs a verified archive. Merging into an existing account takes no secret; a new account needs
    /// its new six-digit account code as `passphrase` (SDK `native_restore_setup`).
    func install(account: String?, expected: BackupRecord, credentials: SensitiveSubmission?, operationID: String) async -> RepositoryResult<BackupRecord>
    func cancel(account: String?, jobID: String, operationID: String) async -> RepositoryResult<Void>
    /// Deletes the private archive file of a finished job (written backup or imported copy).
    func discard(account: String?, job: BackupRecord) async -> RepositoryResult<Void>
}
public actor NativeBackupRepository: BackupRepository {
    /// Session key for jobs started before any account exists.
    private static let newInstall = ""
    private let gateway: ProxyGateway
    private let files: BackupFiles
    private let updates: NativeUpdateSource
    private var ownedJobs: [String: Set<String>] = [:]
    private var paths: [String: String] = [:]
    private let pager = SnapshotPager<BackupRecord>()
    public init(client: RamfluxClient, directory: URL, updates: NativeUpdateSource) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); files = BackupFiles(root: directory); self.updates = updates
    }
    public func observe(account: String?) async -> RepositoryObservation {
        if let account { return await updates.observe(account: account) }
        return await updates.observeBackupJobs()
    }
    public func jobs(account: String?) async -> RepositoryResult<[BackupRecord]> {
        do {
            let body = try await gateway.call(.accountBackupJobs, account: account)
            let owned = ownedJobs[account ?? Self.newInstall] ?? []
            let rows = try ProxyGateway.rows(body, "jobs").map(map).filter { (account != nil && $0.accountID == account) || owned.contains($0.id) }
            guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }
            return .success(rows.sorted { $0.sequence > $1.sequence })
        } catch { return .failure(Self.failure(error)) }
    }
    public func jobsPage(account: String?, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<BackupRecord>> {
        await pager.page(cursor: cursor, limit: limit, read: { await self.jobs(account: account) })
    }
    public func create(account: String, credentials: SensitiveSubmission, allowMissingAttachments: Bool, operationID: String) async -> RepositoryResult<BackupRecord> {
        defer { credentials.erase() }
        if let issue = credentials.archivePassphraseIssue { return .failure(.backup(issue)) }
        guard let fields = credentials.take(), fields["passphrase"] != nil else { return .failure(.backup(.passphraseEmpty)) }
        do {
            let path = try await files.exportPath()
            let body = try await gateway.call(.accountBackupCreate, account: account, body: .object(["output_path": .string(path.path), "allow_missing_attachments": .bool(allowMissingAttachments)]), operationID: operationID, secrets: fields)
            return .success(own(try map(body), account: account))
        } catch { return .failure(Self.failure(error)) }
    }
    public func verify(account: String?, source: URL, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> {
        defer { credentials.erase() }
        if let issue = credentials.archivePassphraseIssue { return .failure(.backup(issue)) }
        guard let fields = credentials.take(), fields["passphrase"] != nil else { return .failure(.backup(.passphraseEmpty)) }
        var copied: URL?
        do {
            let path = try await files.copyImport(source); copied = path
            let body = try await gateway.call(.accountRestoreVerify, account: account, body: .object(["input_path": .string(path.path)]), operationID: operationID, secrets: fields)
            return .success(own(try map(body), account: account))
        } catch {
            // A refused request started no job, so nothing else will ever remove the private copy.
            if let copied { await files.remove(path: copied.path) }
            return .failure(Self.failure(error))
        }
    }
    public func install(account: String?, expected: BackupRecord, credentials: SensitiveSubmission?, operationID: String) async -> RepositoryResult<BackupRecord> {
        defer { credentials?.erase() }
        guard expected.kind == "restore", expected.state == "verified", expected.accountID != nil, let merge = expected.merge else { return .failure(.invalidInput) }
        var secrets: [String: SecretField] = [:]
        if merge {
            // The SDK refuses a setup secret when the archive merges into an existing account.
            guard credentials == nil else { return .failure(.invalidInput) }
        } else {
            guard let credentials else { return .failure(.backup(.restoreSetupRequired)) }
            if let issue = credentials.accountCodeIssue { return .failure(.accountCode(issue)) }
            guard let fields = credentials.take(), fields["passphrase"] != nil else { return .failure(.backup(.restoreSetupRequired)) }
            secrets = fields
        }
        switch await jobs(account: account) {
        case .failure(let failure): return .failure(failure)
        case .success(let rows):
            guard rows.contains(where: { $0.id == expected.id && $0.sequence == expected.sequence && $0.state == "verified" && $0.accountID == expected.accountID && $0.merge == merge }) else { return .failure(.invalidData) }
        }
        do { return .success(try map(await gateway.call(.accountRestoreInstall, account: account, body: .object(["job_id": .string(expected.id)]), operationID: operationID, secrets: secrets))) }
        catch { return .failure(Self.failure(error)) }
    }
    public func cancel(account: String?, jobID: String, operationID: String) async -> RepositoryResult<Void> {
        switch await jobs(account: account) {
        case .failure(let failure): return .failure(failure)
        case .success(let rows):
            guard rows.contains(where: { $0.id == jobID && ["preparing", "writing", "verifying", "verified"].contains($0.state) }) else { return .failure(.invalidInput) }
        }
        do { _ = try await gateway.call(.accountBackupCancel, account: account, body: .object(["job_id": .string(jobID)]), operationID: operationID); return .success(()) }
        catch { return .failure(Self.failure(error)) }
    }
    public func discard(account: String?, job: BackupRecord) async -> RepositoryResult<Void> {
        guard job.isTerminal, ownedJobs[account ?? Self.newInstall]?.contains(job.id) == true || job.accountID == account else { return .failure(.invalidInput) }
        if let path = paths[job.id] ?? job.shareURL?.path { await files.remove(path: path) }
        paths[job.id] = nil
        return .success(())
    }
    private func own(_ row: BackupRecord, account: String?) -> BackupRecord {
        ownedJobs[account ?? Self.newInstall, default: []].insert(row.id); return row
    }
    static func failure(_ error: any Error) -> AppFailure {
        if let failure = error as? CoreFailure {
            let code = failure.reasonCode ?? failure.response?["error"]?["code"]?.string
            if failure.response?["error"]?["code"]?.string == "CapabilityDenied" { return .backup(.attendanceRequired) }
            if let code, code != "BackupRefused", BackupIssue.sdk(code) != .other { return .backup(BackupIssue.sdk(code)) }
        }
        return AppFailure.map(error)
    }
    private func map(_ response: JSONValue) throws -> BackupRecord {
        let body = response["job"] ?? response
        let kind = try ProxyGateway.text(body, "kind"), state = try ProxyGateway.text(body, "state")
        guard ["backup","restore"].contains(kind), ["preparing","writing","verifying","verified","installing","done","failed","cancelled"].contains(state) else { throw AppFailure.invalidData }
        guard let sequence = Self.unsigned(body["seq"]) else { throw AppFailure.invalidData }
        let id = try ProxyGateway.text(body, "job_id")
        let privateFile = body["path"]?.string.flatMap { files.shareURL(path: $0) }
        if let privateFile { paths[id] = privateFile.path }
        let share = kind == "backup" && state == "done" ? privateFile : nil
        let progress = body["progress"].flatMap { value -> BackupRecord.Progress? in
            guard let category = value["category"]?.string, let items = Self.unsigned(value["items_done"]), let bytes = Self.unsigned(value["bytes_done"]) else { return nil }
            return BackupRecord.Progress(category: category, itemsDone: items, itemsTotal: Self.unsigned(value["items_total"]), bytesDone: bytes, bytesTotal: Self.unsigned(value["bytes_total"]))
        }
        let failure = body["error"].flatMap { value -> BackupRecord.Failure? in
            guard let code = value["code"]?.string else { return nil }
            return BackupRecord.Failure(code: code, retryable: value["retryable"]?.bool ?? false, neededBytes: Self.unsigned(value["needed_bytes"]),
                availableBytes: Self.unsigned(value["available_bytes"]), unavailableCount: Self.unsigned(value["unavailable_count"]))
        }
        let label = body["archive"]?["account_label"]?.string.map { String($0.prefix(256)) }
        return BackupRecord(id: id, kind: kind, state: state, sequence: sequence,
            accountID: body["archive"]?["local_account_id"]?.string ?? body["installed_account"]?["local_account_id"]?.string,
            merge: body["archive"]?["merge"]?.bool, shareURL: share, progress: progress, failure: failure, accountLabel: label,
            archiveCreatedAt: Self.unsigned(body["archive"]?["created_at"]), archiveBytes: Self.unsigned(body["archive_bytes"]),
            installedAccountID: body["installed_account"]?["local_account_id"]?.string)
    }
    private static func unsigned(_ value: JSONValue?) -> UInt64? {
        switch value { case .unsigned(let value): value; case .string(let value): UInt64(value); case .number(let value): UInt64(exactly: value); default: nil }
    }
}
public struct UnavailableBackupRepository: BackupRepository {
    public init() {}
    public func jobs(account: String?) async -> RepositoryResult<[BackupRecord]> { .failure(.sdkUnavailable) }
    public func observe(account: String?) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
    public func jobsPage(account: String?, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<BackupRecord>> { .failure(.sdkUnavailable) }
    public func create(account: String, credentials: SensitiveSubmission, allowMissingAttachments: Bool, operationID: String) async -> RepositoryResult<BackupRecord> { credentials.erase(); return .failure(.sdkUnavailable) }
    public func verify(account: String?, source: URL, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> { credentials.erase(); return .failure(.sdkUnavailable) }
    public func install(account: String?, expected: BackupRecord, credentials: SensitiveSubmission?, operationID: String) async -> RepositoryResult<BackupRecord> { credentials?.erase(); return .failure(.sdkUnavailable) }
    public func cancel(account: String?, jobID: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func discard(account: String?, job: BackupRecord) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
}
