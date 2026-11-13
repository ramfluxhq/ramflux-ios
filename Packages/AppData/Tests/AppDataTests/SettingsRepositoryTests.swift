// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData

@Suite(.timeLimit(.minutes(1))) struct SettingsRepositoryTests {
    @Test func localDeviceAndInvalidRetentionNeverReachSDK() async {
        let transport = ProxyTransport { _ in .object([:]) }, client = RamfluxClient(transport: ProxyTransport { _ in .object([:]) })
        let repository = NativeSettingsRepository(client: RamfluxClient(transport: transport), nodes: UnavailableNodeRepository(), updates: NativeUpdateSource(client: client))
        guard case .failure(.invalidInput) = await repository.revoke(account: "a", device: DeviceRecord(id: "local", isLocal: true, capabilities: []), operationID: "key") else { Issue.record("Local device revoke was not refused"); return }
        guard case .failure(.invalidInput) = await repository.retention(account: "a", seconds: 1, operationID: "key") else { Issue.record("Invalid retention was not refused"); return }
        #expect(transport.calls.withLock { $0.isEmpty })
        _ = await repository.requireManualRequests(account: "a", operationID: "manual")
        #expect(transport.calls.withLock { $0.last?.body["contact_requests"] } == .string("manual"))
    }
    @Test func jobWrapperPreservesExactSequenceAndRestoreChecksCurrentProjection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let row: JSONValue = .object(["job_id": .string("job"), "kind": .string("restore"), "state": .string("verified"), "seq": .unsigned(UInt64.max), "archive": .object(["local_account_id": .string("a"), "merge": .bool(true)])])
        let transport = ProxyTransport { request in
            switch request.method {
            case "account.restore.verify", "account.restore.install": .object(["job": row])
            case "account.backup.jobs": .object(["jobs": .array([row])])
            default: .object([:])
            }
        }
        let repository = NativeBackupRepository(client: RamfluxClient(transport: transport), directory: directory.appendingPathComponent("private"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.rfb"); try Data([1,2,3]).write(to: source)
        guard case .success(let verified) = await repository.verify(account: "a", source: source, credentials: SensitiveSubmission(values: ["passphrase": "test"]), operationID: "verify") else { Issue.record("Wrapped verify job rejected"); return }
        #expect(verified.sequence == UInt64.max); #expect(verified.merge == true)
        let stale = BackupRecord(id: "job", kind: "restore", state: "verified", sequence: 1, accountID: "a")
        guard case .failure(.invalidData) = await repository.install(account: "a", expected: stale, credentials: SensitiveSubmission(values: ["passphrase": "test"]), operationID: "stale") else { Issue.record("Stale restore job accepted"); return }
        #expect(!transport.calls.withLock { $0.contains { $0.method == "account.restore.install" } })
        guard case .success = await repository.install(account: "a", expected: verified, credentials: SensitiveSubmission(values: ["passphrase": "test"]), operationID: "install") else { Issue.record("Exact restore job refused"); return }
        guard case .success(let others) = await repository.jobs(account: "another") else { Issue.record("Listing failed"); return }
        #expect(others.isEmpty)
    }
    @Test func importsCopyPrivatelyAndSharingRejectsOutsideFilesAndSymlinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.rfb"), bytes = Data([1,2,3,4])
        try bytes.write(to: source)
        let files = BackupFiles(root: directory.appendingPathComponent("private")), copied = try await files.copyImport(source)
        #expect(copied != source); #expect(try Data(contentsOf: copied) == bytes)
        #expect(files.shareURL(path: copied.path) == copied); #expect(files.shareURL(path: source.path) == nil)
        let link = copied.deletingLastPathComponent().appendingPathComponent("link.rfb")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        #expect(files.shareURL(path: link.path) == nil)
        do { _ = try await files.copyImport(link); Issue.record("Symlink import accepted") } catch {}
        let empty = directory.appendingPathComponent("empty.rfb"); try Data().write(to: empty)
        do { _ = try await files.copyImport(empty); Issue.record("Empty archive accepted") } catch {}
    }
    @Test func attendedFrontendIsAnExplicitOptIn() throws {
        #expect(try SubscriptionFilter(topics: []).body["attended_frontend"] == nil)
        #expect(try SubscriptionFilter(topics: [], attendedFrontend: true).body["attended_frontend"] == .bool(true))
    }
}
