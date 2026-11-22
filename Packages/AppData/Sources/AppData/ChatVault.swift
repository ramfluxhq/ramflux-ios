// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CryptoKit
import Security
import RamfluxCore

/// Unsent chat state of one account as it is sealed on disk: queued and failed sends with their
/// original operation ids, composer drafts, and erase-for-everyone revokes still to retry.
/// Media items are stored by their outbox file name only; the directory is resolved again on load
/// because the app container path can change between launches.
struct ChatVaultSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable { var name: String; var fileName: String; var mime: String }
    struct Entry: Codable, Equatable, Sendable {
        var operationID: String
        var text: String
        var created: Int64
        /// Nil while queued; otherwise the encoded failure (see `ChatVault.encode`).
        var failure: String?
        var groupID: String?
        var media: [Item]
    }
    var outbox: [String: [Entry]] = [:]
    var drafts: [String: String] = [:]
    var revokes: [String] = []
    var isEmpty: Bool { outbox.values.allSatisfy(\.isEmpty) && drafts.isEmpty && revokes.isEmpty }
}

/// The 256-bit key that seals an account's chat vault.
protocol ChatVaultKeys: Sendable {
    /// Loads the account's key, or creates and stores a new one when there is none (or the
    /// sealed file it belonged to is gone).
    func key(account: String, sealedFile: URL) async throws -> SymmetricKey
    func remove(account: String) async
}

/// Keys in the app-private keychain (this device only, never synchronised), through the core's
/// keychain vault. A new key is drawn from the system random source and stored before use.
struct KeychainChatVaultKeys: ChatVaultKeys {
    private let vault = KeychainVault(service: "org.ramflux.chat.vault")
    func key(account: String, sealedFile: URL) async throws -> SymmetricKey {
        do {
            let secret = try await vault.load(account: account, existingDatabase: sealedFile)
            return try secret.consume { SymmetricKey(data: $0) }
        } catch BridgeError.orphanedVault {
            try await vault.remove(account: account)
        } catch BridgeError.missingVault {}
        var bytes = [UInt8](repeating: 0, count: 32)
        defer { bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppFailure.localStorage }
        let key = bytes.withUnsafeBytes { SymmetricKey(data: $0) }
        let secret = try bytes.withUnsafeBytes { try SecretBytes(copying: $0) }
        try await vault.store(secret, account: account)
        return key
    }
    func remove(account: String) async { try? await vault.remove(account: account) }
}

/// The sealed per-account store under Application Support: one AES-GCM sealed file per account,
/// written atomically with complete file protection and excluded from backup. Nothing in it is
/// readable without the keychain key; erasing the account deletes both.
struct ChatVault: Sendable {
    let base: URL
    let keys: any ChatVaultKeys
    /// The account's media outbox, where staged files of queued media sends live.
    let outbox: @Sendable (String) -> URL
    init(base: URL? = nil, keys: any ChatVaultKeys = KeychainChatVaultKeys(), outbox: @escaping @Sendable (String) -> URL) {
        self.base = base ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("RamfluxChat", isDirectory: true)
        self.keys = keys; self.outbox = outbox
    }
    func file(_ account: String) -> URL { base.appendingPathComponent(MediaStore.hash(account) + ".sealed") }

    /// The stored snapshot; empty when nothing was stored or the file cannot be opened (a key
    /// lost with a reinstall makes the old file unreadable, and it is replaced on the next save).
    func load(_ account: String) async -> ChatVaultSnapshot {
        let url = file(account)
        guard FileManager.default.fileExists(atPath: url.path), let sealed = try? Data(contentsOf: url),
              let key = try? await keys.key(account: MediaStore.hash(account), sealedFile: url),
              let box = try? AES.GCM.SealedBox(combined: sealed), let plain = try? AES.GCM.open(box, using: key, authenticating: Data(account.utf8)) else { return ChatVaultSnapshot() }
        return (try? JSONDecoder().decode(ChatVaultSnapshot.self, from: plain)) ?? ChatVaultSnapshot()
    }

    /// Seals and writes the snapshot, or erases the file when nothing is left to keep.
    func save(_ account: String, _ snapshot: ChatVaultSnapshot) async throws {
        let url = file(account)
        guard !snapshot.isEmpty else { try? FileManager.default.removeItem(at: url); return }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var root = base, values = URLResourceValues(); values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        let key = try await keys.key(account: MediaStore.hash(account), sealedFile: url)
        let plain = try JSONEncoder().encode(snapshot)
        guard let sealed = try AES.GCM.seal(plain, using: key, authenticating: Data(account.utf8)).combined else { throw AppFailure.localStorage }
        #if os(iOS)
        try sealed.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try sealed.write(to: url, options: [.atomic])
        #endif
    }

    func erase(_ account: String) async {
        try? FileManager.default.removeItem(at: file(account))
        await keys.remove(account: MediaStore.hash(account))
    }

    // MARK: Mapping

    static func encode(_ entry: OutboxEntry) -> ChatVaultSnapshot.Entry {
        let failure: String? = switch entry.state {
        case .queued, .sending: nil
        case .failed(.typedRefusal(let name)): "t:" + name
        case .failed(.unavailableResource(let key)): "u:" + key
        case .failed(.offline): nil
        case .failed: "f"
        }
        return ChatVaultSnapshot.Entry(operationID: entry.operationID, text: entry.text, created: entry.created, failure: failure, groupID: entry.groupID,
                                       media: entry.media.map { ChatVaultSnapshot.Item(name: $0.file.lastPathComponent, fileName: $0.fileName, mime: $0.mime) })
    }

    /// A media entry whose staged files are gone cannot be sent again: it comes back failed.
    func decode(_ entry: ChatVaultSnapshot.Entry, account: String) -> OutboxEntry {
        let directory = outbox(account)
        let unsafe = entry.media.contains { $0.name.contains("/") || $0.name == "." || $0.name == ".." || $0.name.isEmpty }
        let media = unsafe ? [] : entry.media.map { MediaUpload(file: directory.appendingPathComponent($0.name), fileName: $0.fileName, mime: $0.mime) }
        var state: OutboxEntry.State = switch entry.failure {
        case nil: .queued
        case let value? where value.hasPrefix("t:"): .failed(.typedRefusal(String(value.dropFirst(2))))
        case let value? where value.hasPrefix("u:"): .failed(.unavailableResource(String(value.dropFirst(2))))
        default: .failed(.failed)
        }
        if unsafe || media.contains(where: { !FileManager.default.fileExists(atPath: $0.file.path) }) { state = .failed(.localStorage) }
        return OutboxEntry(operationID: entry.operationID, text: entry.text, created: entry.created, state: state, groupID: entry.groupID, media: media)
    }
}
