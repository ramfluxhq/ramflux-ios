// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// An account created or restored on this device. Public facts only: no code, phrase, key or token.
public struct KnownAccount: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var displayName: String
    /// Discovery origin of the account's node, when the device knew it at creation.
    public var nodeOrigin: String?
    public let createdAt: Date
    public init(id: String, displayName: String, nodeOrigin: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.displayName = displayName; self.nodeOrigin = nodeOrigin; self.createdAt = createdAt
    }
}

/// The accounts this device created or restored, so that unlock and account switch can offer them while
/// the SDK's `account.list` reports only open accounts. The SDK stays the authority: an entry is only an
/// offer, and unlocking it goes through `account.unlock` like any other account.
public protocol KnownAccountRegistry: Sendable {
    func all() async -> [KnownAccount]
    /// Adds the account, or refreshes its display name (and node origin when one is given).
    func record(_ account: KnownAccount) async
    func remove(_ id: String) async
}

/// The registry in one small JSON file in app-private storage, excluded from device backup.
public actor FileKnownAccountRegistry: KnownAccountRegistry {
    static let maxEntries = 64
    private let file: URL
    private var cache: [KnownAccount]?
    public init(file: URL) { self.file = file }
    /// `Application Support/known-accounts.json`, beside (not inside) the SDK data root.
    public static func standard() -> FileKnownAccountRegistry? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return FileKnownAccountRegistry(file: support.appendingPathComponent("known-accounts.json", isDirectory: false))
    }
    public func all() -> [KnownAccount] { load() }
    public func record(_ account: KnownAccount) {
        guard Self.valid(account) else { return }
        var entries = load()
        if let index = entries.firstIndex(where: { $0.id == account.id }) {
            entries[index].displayName = account.displayName
            if let origin = account.nodeOrigin { entries[index].nodeOrigin = origin }
        } else {
            entries.append(account)
            if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        }
        save(entries)
    }
    public func remove(_ id: String) {
        var entries = load()
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        save(entries)
    }
    static func valid(_ account: KnownAccount) -> Bool {
        !account.id.isEmpty && account.id.utf8.count <= 256 && account.displayName.utf8.count <= 1024 && (account.nodeOrigin?.utf8.count ?? 0) <= 2048
    }
    private func load() -> [KnownAccount] {
        if let cache { return cache }
        let decoded = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([KnownAccount].self, from: $0) } ?? []
        var seen = Set<String>()
        let entries = decoded.filter { Self.valid($0) && seen.insert($0.id).inserted }.suffix(Self.maxEntries)
        cache = Array(entries); return Array(entries)
    }
    private func save(_ entries: [KnownAccount]) {
        cache = entries
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: [.atomic])
            #endif
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var target = file; try target.setResourceValues(values)
        } catch {
            // The registry is a convenience; the SDK still lists open accounts and unlock by id stays possible.
        }
    }
}

/// Process-memory registry (tests, source-only builds).
public actor MemoryKnownAccountRegistry: KnownAccountRegistry {
    private var entries: [KnownAccount]
    public init(_ entries: [KnownAccount] = []) { self.entries = entries }
    public func all() -> [KnownAccount] { entries }
    public func record(_ account: KnownAccount) {
        if let index = entries.firstIndex(where: { $0.id == account.id }) {
            entries[index].displayName = account.displayName
            if let origin = account.nodeOrigin { entries[index].nodeOrigin = origin }
        } else { entries.append(account) }
    }
    public func remove(_ id: String) { entries.removeAll { $0.id == id } }
}

extension SessionSnapshot {
    /// The SDK's open accounts named from the registry, followed by the registry's other accounts as locked.
    public static func merging(_ open: SessionSnapshot, known: [KnownAccount]) -> SessionSnapshot {
        let names = Dictionary(known.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let openIDs = Set(open.accounts.map(\.id))
        let named = open.accounts.map { account in
            AccountRecord(id: account.id, displayName: names[account.id].flatMap { $0.isEmpty ? nil : $0 } ?? account.displayName, isLocked: account.isLocked, networking: account.networking)
        }
        let locked = known.filter { !openIDs.contains($0.id) }.map { AccountRecord(id: $0.id, displayName: $0.displayName.isEmpty ? $0.id : $0.displayName, isLocked: true) }
        return SessionSnapshot(phase: open.phase, accounts: named + locked, activeAccountID: open.activeAccountID)
    }
}
