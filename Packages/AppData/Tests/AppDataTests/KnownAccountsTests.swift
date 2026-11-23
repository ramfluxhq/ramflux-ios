// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import AppData

@Suite(.timeLimit(.minutes(1))) struct KnownAccountsTests {
    @Test func fileRegistryRecordsRenamesRemovesAndPersistsOutsideBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("known-accounts.json")
        let registry = FileKnownAccountRegistry(file: file)
        #expect(await registry.all().isEmpty)
        await registry.record(KnownAccount(id: "account-a", displayName: "Ada", nodeOrigin: "http://127.0.0.1:8482"))
        await registry.record(KnownAccount(id: "account-b", displayName: "Bo"))
        // A later record (an unlock) refreshes the name and keeps the known origin.
        await registry.record(KnownAccount(id: "account-a", displayName: "Ada L."))
        let reopened = FileKnownAccountRegistry(file: file)
        let entries = await reopened.all()
        #expect(entries.map(\.id) == ["account-a", "account-b"])
        #expect(entries.first?.displayName == "Ada L.")
        #expect(entries.first?.nodeOrigin == "http://127.0.0.1:8482")
        let excluded = try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        #expect(excluded == true)
        // Only public facts are stored.
        let stored = try String(contentsOf: file, encoding: .utf8)
        #expect(!stored.contains("passphrase") && !stored.contains("phrase"))
        await reopened.remove("account-a")
        #expect(await FileKnownAccountRegistry(file: file).all().map(\.id) == ["account-b"])
    }

    @Test func fileRegistryIgnoresCorruptOrInvalidEntries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("known-accounts.json")
        try Data("not json".utf8).write(to: file)
        let registry = FileKnownAccountRegistry(file: file)
        #expect(await registry.all().isEmpty)
        await registry.record(KnownAccount(id: "", displayName: "nobody"))
        #expect(await registry.all().isEmpty)
    }

    @Test func mergingNamesOpenAccountsAndOffersTheOthersLocked() {
        let open = SessionSnapshot(phase: .ready, accounts: [AccountRecord(id: "account-a", displayName: "account-a", isLocked: false)], activeAccountID: "account-a")
        let known = [KnownAccount(id: "account-a", displayName: "Ada"), KnownAccount(id: "account-b", displayName: "Bo")]
        let merged = SessionSnapshot.merging(open, known: known)
        #expect(merged.accounts == [AccountRecord(id: "account-a", displayName: "Ada", isLocked: false), AccountRecord(id: "account-b", displayName: "Bo", isLocked: true)])
        #expect(merged.activeAccountID == "account-a")
        // After lock or a cold start the SDK lists nothing; the registry still offers the account.
        let cold = SessionSnapshot.merging(SessionSnapshot(phase: .ready), known: known)
        #expect(cold.accounts.allSatisfy { $0.isLocked })
        #expect(cold.activeAccountID == nil)
    }
}
