// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public protocol BackupRepository: Sendable {
    func jobs(account: String) async -> RepositoryResult<[BackupRecord]>
    func create(account: String, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord>
    func verify(account: String, source: URL, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord>
    func install(account: String, expected: BackupRecord, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord>
    func cancel(account: String, jobID: String, operationID: String) async -> RepositoryResult<Void>
}
public actor NativeBackupRepository: BackupRepository {
    private let gateway: ProxyGateway
    private let files: BackupFiles
    private var ownedJobs: [String: Set<String>] = [:]
    public init(client: RamfluxClient, directory: URL) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); files = BackupFiles(root: directory) }
    public func jobs(account: String) async -> RepositoryResult<[BackupRecord]> {
        do {
            let body = try await gateway.call(.accountBackupJobs, account: account)
            let rows = try ProxyGateway.rows(body, "jobs").map(map).filter { $0.accountID == account || ownedJobs[account]?.contains($0.id) == true }
            guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }; return .success(rows)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func create(account: String, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> {
        defer { credentials.erase() }
        guard let fields = credentials.take(), fields["passphrase"] != nil else { return .failure(.invalidInput) }
        do {
            let path = try await files.exportPath()
            let body = try await gateway.call(.accountBackupCreate, account: account, body: .object(["output_path": .string(path.path), "allow_missing_attachments": .bool(false)]), operationID: operationID, secrets: fields)
            let row = try map(body); ownedJobs[account, default: []].insert(row.id); return .success(row)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func verify(account: String, source: URL, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> {
        defer { credentials.erase() }
        guard let fields = credentials.take(), fields["passphrase"] != nil else { return .failure(.invalidInput) }
        do {
            let path = try await files.copyImport(source)
            let body = try await gateway.call(.accountRestoreVerify, account: account, body: .object(["input_path": .string(path.path)]), operationID: operationID, secrets: fields)
            let row = try map(body); ownedJobs[account, default: []].insert(row.id); return .success(row)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func install(account: String, expected: BackupRecord, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> {
        defer { credentials.erase() }
        guard expected.kind == "restore", expected.state == "verified", expected.accountID != nil,
              let fields = credentials.take(), fields["passphrase"] != nil else { return .failure(.invalidInput) }
        switch await jobs(account: account) {
        case .failure(let failure): return .failure(failure)
        case .success(let rows):
            guard rows.contains(where: { $0.id == expected.id && $0.sequence == expected.sequence && $0.state == "verified" && $0.accountID == expected.accountID }) else { return .failure(.invalidData) }
        }
        do { return .success(try map(await gateway.call(.accountRestoreInstall, account: account, body: .object(["job_id": .string(expected.id)]), operationID: operationID, secrets: fields))) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func cancel(account: String, jobID: String, operationID: String) async -> RepositoryResult<Void> {
        switch await jobs(account: account) {
        case .failure(let failure): return .failure(failure)
        case .success(let rows):
            guard rows.contains(where: { $0.id == jobID && ["preparing", "writing", "verifying"].contains($0.state) }) else { return .failure(.invalidInput) }
        }
        do { _ = try await gateway.call(.accountBackupCancel, account: account, body: .object(["job_id": .string(jobID)]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    private func map(_ response: JSONValue) throws -> BackupRecord {
        let body = response["job"] ?? response
        let kind = try ProxyGateway.text(body, "kind"), state = try ProxyGateway.text(body, "state")
        guard ["backup","restore"].contains(kind), ["preparing","writing","verifying","verified","installing","done","failed","cancelled"].contains(state) else { throw AppFailure.invalidData }
        let sequence: UInt64?
        switch body["seq"] { case .unsigned(let value): sequence = value; case .string(let value): sequence = UInt64(value); case .number(let value): sequence = UInt64(exactly: value); default: sequence = nil }
        guard let sequence else { throw AppFailure.invalidData }
        let share = kind == "backup" && state == "done" ? body["path"]?.string.flatMap { files.shareURL(path: $0) } : nil
        return BackupRecord(id: try ProxyGateway.text(body, "job_id"), kind: kind, state: state, sequence: sequence,
            accountID: body["archive"]?["local_account_id"]?.string, merge: body["archive"]?["merge"]?.bool, shareURL: share)
    }
}
public struct UnavailableBackupRepository: BackupRepository {
    public init() {}
    public func jobs(account: String) async -> RepositoryResult<[BackupRecord]> { .failure(.sdkUnavailable) }
    public func create(account: String, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> { credentials.erase(); return .failure(.sdkUnavailable) }
    public func verify(account: String, source: URL, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> { credentials.erase(); return .failure(.sdkUnavailable) }
    public func install(account: String, expected: BackupRecord, credentials: SensitiveSubmission, operationID: String) async -> RepositoryResult<BackupRecord> { credentials.erase(); return .failure(.sdkUnavailable) }
    public func cancel(account: String, jobID: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
}
