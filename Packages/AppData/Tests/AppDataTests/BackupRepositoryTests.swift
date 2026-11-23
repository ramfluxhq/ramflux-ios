// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import RamfluxCore
@testable import AppData

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
private func repository(_ transport: ProxyTransport, _ directory: URL) -> NativeBackupRepository {
    let client = RamfluxClient(transport: transport)
    return NativeBackupRepository(client: client, directory: directory.appendingPathComponent("private"), updates: NativeUpdateSource(client: client))
}
private func restoreRow(id: String = "job", state: String = "verified", merge: Bool, account: String = "a", seq: UInt64 = 7) -> JSONValue {
    .object(["job_id": .string(id), "kind": .string("restore"), "state": .string(state), "seq": .unsigned(seq),
             "archive": .object(["local_account_id": .string(account), "merge": .bool(merge), "account_label": .string("Ada"), "created_at": .unsigned(1_700_000_000)])])
}
private func methods(_ transport: ProxyTransport) -> [String] { transport.calls.withLock { $0.map(\.method) } }

@Suite(.timeLimit(.minutes(1))) struct BackupRepositoryTests {
    @Test func mergeInstallSendsNoSecretAndChecksTheCurrentProjection() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let row = restoreRow(merge: true, seq: UInt64.max)
        let transport = ProxyTransport { request in
            switch request.method {
            case "account.restore.verify", "account.restore.install": .object(["job": row])
            case "account.backup.jobs": .object(["jobs": .array([row])])
            default: .object([:])
            }
        }
        let backups = repository(transport, directory)
        let source = directory.appendingPathComponent("source.rfb"); try Data([1, 2, 3]).write(to: source)
        guard case .success(let verified) = await backups.verify(account: "a", source: source, credentials: SensitiveSubmission(values: ["passphrase": "archive"], archivePassphrase: .existing), operationID: "verify") else { Issue.record("verify refused"); return }
        #expect(verified.sequence == UInt64.max); #expect(verified.merge == true); #expect(verified.accountLabel == "Ada"); #expect(verified.archiveCreatedAt == 1_700_000_000)
        let stale = BackupRecord(id: "job", kind: "restore", state: "verified", sequence: 1, accountID: "a", merge: true)
        guard case .failure(.invalidData) = await backups.install(account: "a", expected: stale, credentials: nil, operationID: "stale") else { Issue.record("stale job accepted"); return }
        guard case .failure(.invalidInput) = await backups.install(account: "a", expected: verified, credentials: SensitiveSubmission(values: ["passphrase": "246810"]), operationID: "secret") else { Issue.record("merge accepted a setup secret"); return }
        #expect(!methods(transport).contains("account.restore.install"))
        guard case .success = await backups.install(account: "a", expected: verified, credentials: nil, operationID: "install") else { Issue.record("exact job refused"); return }
        guard case .success(let others) = await backups.jobs(account: "another") else { Issue.record("listing failed"); return }
        #expect(others.isEmpty)
    }
    @Test func newInstallRestoreListsOnlyOwnJobsAndNeedsAValidNewAccountCode() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let row = restoreRow(merge: false, account: "restore-x")
        let foreign = restoreRow(id: "foreign", merge: false, account: "restore-y")
        let transport = ProxyTransport { request in
            switch request.method {
            case "account.restore.verify": .object(["job": row])
            case "account.restore.install": .object(["job": restoreRow(state: "installing", merge: false, account: "restore-x")])
            case "account.backup.jobs": .object(["jobs": .array([foreign, row])])
            default: .object([:])
            }
        }
        let backups = repository(transport, directory)
        let source = directory.appendingPathComponent("source.rfb"); try Data([9]).write(to: source)
        guard case .success(let verified) = await backups.verify(account: nil, source: source, credentials: SensitiveSubmission(values: ["passphrase": "archive"], archivePassphrase: .existing), operationID: "v") else { Issue.record("verify refused"); return }
        #expect(transport.calls.withLock { $0.last?.accountID } == nil)
        guard case .success(let listed) = await backups.jobs(account: nil) else { Issue.record("listing failed"); return }
        #expect(listed.map(\.id) == ["job"])
        guard case .failure(.backup(.restoreSetupRequired)) = await backups.install(account: nil, expected: verified, credentials: nil, operationID: "i0") else { Issue.record("install without a code accepted"); return }
        let trivial = SensitiveSubmission(values: ["passphrase": "123456", "passphraseRepeat": "123456"], accountCode: .new)
        guard case .failure(.accountCode(.trivial)) = await backups.install(account: nil, expected: verified, credentials: trivial, operationID: "i1") else { Issue.record("trivial code accepted"); return }
        #expect(!methods(transport).contains("account.restore.install"))
        let code = SensitiveSubmission(values: ["passphrase": "274915", "passphraseRepeat": "274915"], accountCode: .new)
        guard case .success(let installing) = await backups.install(account: nil, expected: verified, credentials: code, operationID: "i2") else { Issue.record("valid code refused"); return }
        #expect(installing.state == "installing")
        #expect(transport.calls.withLock { $0.last?.method } == "account.restore.install")
    }
    @Test func archivePassphrasePrecheckNeverReachesTheSDK() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let transport = ProxyTransport { _ in .object([:]) }
        let backups = repository(transport, directory)
        let short = SensitiveSubmission(values: ["passphrase": "short", "passphraseRepeat": "short"], archivePassphrase: .new)
        guard case .failure(.backup(.passphraseTooShort)) = await backups.create(account: "a", credentials: short, allowMissingAttachments: false, operationID: "c1") else { Issue.record("short passphrase accepted"); return }
        let mismatch = SensitiveSubmission(values: ["passphrase": "correct horse battery", "passphraseRepeat": "correct horse battery!"], archivePassphrase: .new)
        guard case .failure(.backup(.passphraseMismatch)) = await backups.create(account: "a", credentials: mismatch, allowMissingAttachments: false, operationID: "c2") else { Issue.record("mismatch accepted"); return }
        guard case .failure(.backup(.passphraseEmpty)) = await backups.verify(account: "a", source: directory, credentials: SensitiveSubmission(values: [:], archivePassphrase: .existing), operationID: "v") else { Issue.record("empty accepted"); return }
        #expect(transport.calls.withLock { $0.isEmpty })
    }
    @Test func createParsesProgressAndFailureAndAllowsMissingAttachmentsOnRequest() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let row: JSONValue = .object(["job_id": .string("b"), "kind": .string("backup"), "state": .string("failed"), "seq": .number(3),
            "progress": .object(["category": .string("messages"), "items_done": .number(4), "items_total": .number(9), "bytes_done": .number(100)]),
            "error": .object(["code": .string("attachments_unavailable"), "unavailable_count": .number(2)])])
        let transport = ProxyTransport { request in request.method == "account.backup.create" ? .object(["job": row]) : .object(["jobs": .array([row])]) }
        let backups = repository(transport, directory)
        let valid = SensitiveSubmission(values: ["passphrase": "a long archive passphrase", "passphraseRepeat": "a long archive passphrase"], archivePassphrase: .new)
        guard case .success(let job) = await backups.create(account: "a", credentials: valid, allowMissingAttachments: true, operationID: "c") else { Issue.record("create refused"); return }
        #expect(job.progress == BackupRecord.Progress(category: "messages", itemsDone: 4, itemsTotal: 9, bytesDone: 100))
        #expect(job.failure?.code == "attachments_unavailable"); #expect(job.failure?.unavailableCount == 2); #expect(job.isTerminal)
        let body = transport.calls.withLock { $0.last?.body }
        #expect(body?["allow_missing_attachments"] == .bool(true))
        #expect(body?["output_path"]?.string?.hasPrefix(directory.appendingPathComponent("private").path) == true)
        guard case .success(let listed) = await backups.jobs(account: "a"), case .success(let unrelated) = await backups.jobs(account: "unrelated") else { Issue.record("listing failed"); return }
        #expect(listed.map(\.id) == ["b"]); #expect(unrelated.isEmpty)
    }
    @Test func refusalsMapToTypedBackupIssuesAndARefusedVerifyLeavesNoCopy() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let reply = Mutex<JSONValue>(.object(["code": .string("CapabilityDenied")]))
        let transport = ProxyTransport { _ in
            throw CoreFailure(code: 7, effect: .none, response: .object(["error": reply.withLock { $0 }]))
        }
        let backups = repository(transport, directory)
        let source = directory.appendingPathComponent("source.rfb"); try Data([1]).write(to: source)
        let passphrase = { SensitiveSubmission(values: ["passphrase": "archive"], archivePassphrase: .existing) }
        guard case .failure(.backup(.attendanceRequired)) = await backups.verify(account: nil, source: source, credentials: passphrase(), operationID: "v1") else { Issue.record("capability denial not typed"); return }
        reply.withLock { $0 = .object(["code": .string("BackupRefused"), "reason_code": .string("wrong_passphrase")]) }
        let wrong = CoreFailure(code: 7, effect: .none, reasonCode: "wrong_passphrase")
        #expect(NativeBackupRepository.failure(wrong) == .backup(.wrongPassphrase))
        #expect(NativeBackupRepository.failure(CoreFailure(code: 7, effect: .none, response: .object(["error": .object(["code": .string("too_common")])]))) == .backup(.passphraseTooCommon))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("private").path)
        #expect(leftovers.isEmpty)
    }
    @Test func oversizeImportIsRefusedBeforeCopying() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("large.rfb")
        #expect(FileManager.default.createFile(atPath: source.path, contents: nil))
        let handle = try FileHandle(forWritingTo: source); try handle.truncate(atOffset: UInt64(BackupFiles.importLimitBytes) + 1); try handle.close()
        let transport = ProxyTransport { _ in .object([:]) }
        let backups = repository(transport, directory)
        guard case .failure(.backup(.importTooLarge)) = await backups.verify(account: "a", source: source, credentials: SensitiveSubmission(values: ["passphrase": "archive"], archivePassphrase: .existing), operationID: "v") else { Issue.record("oversize accepted"); return }
        #expect(transport.calls.withLock { $0.isEmpty })
    }
    @Test func discardRemovesOnlyTheJobsPrivateFile() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let path = Mutex<String>("")
        let transport = ProxyTransport { request in
            let row: JSONValue = .object(["job_id": .string("b"), "kind": .string("backup"), "state": .string("done"), "seq": .number(1), "path": .string(path.withLock { $0 })])
            if request.method == "account.backup.create" {
                let output = request.body["output_path"]?.string ?? ""
                path.withLock { $0 = output }; FileManager.default.createFile(atPath: output, contents: Data([1]))
                return .object(["job": .object(["job_id": .string("b"), "kind": .string("backup"), "state": .string("done"), "seq": .number(1), "path": .string(output)])])
            }
            return .object(["jobs": .array([row])])
        }
        let backups = repository(transport, directory)
        let valid = SensitiveSubmission(values: ["passphrase": "a long archive passphrase", "passphraseRepeat": "a long archive passphrase"], archivePassphrase: .new)
        guard case .success(let job) = await backups.create(account: "a", credentials: valid, allowMissingAttachments: false, operationID: "c") else { Issue.record("create refused"); return }
        #expect(job.shareURL != nil)
        let outside = directory.appendingPathComponent("keep.rfb"); try Data([2]).write(to: outside)
        let forged = BackupRecord(id: "b", kind: "backup", state: "done", sequence: 1, shareURL: outside)
        guard case .success = await backups.discard(account: "a", job: forged) else { Issue.record("discard refused"); return }
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(!FileManager.default.fileExists(atPath: path.withLock { $0 }))
    }
}
