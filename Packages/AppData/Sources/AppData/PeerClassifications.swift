// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// SDK-verified kinds of known people (`verified_classification` on `contact.list`), keyed by principal id
/// and root commitment, for the AI marker on rows the SDK does not classify themselves (conversation
/// rows, group members, message authors). One `contact.list` read serves a whole page; the map is reused
/// for a short time and read again only when a page asks for a principal the map does not know and the
/// last read is not recent. Runs off the main thread (an actor reached from a repository).
actor PeerClassifications {
    private let contacts: any ContactsRepository
    private let now: @Sendable () -> Date
    private var cache: [String: (entries: [String: Entry], read: Date)] = [:]
    struct Entry: Sendable, Equatable { let name: String?; let classification: PrincipalClassification }
    static let freshFor: TimeInterval = 60
    static let missRetryAfter: TimeInterval = 5
    init(_ contacts: any ContactsRepository) { self.init(contacts, now: { Date() }) }
    init(_ contacts: any ContactsRepository, now: @escaping @Sendable () -> Date) { self.contacts = contacts; self.now = now }
    func entries(account: String, wanted: Set<String>) async -> [String: Entry] {
        let current = now()
        if let entry = cache[account] {
            let age = current.timeIntervalSince(entry.read)
            let missing = !wanted.isSubset(of: entry.entries.keys)
            if age < Self.freshFor && (!missing || age < Self.missRetryAfter) { return entry.entries }
        }
        guard case .success(let rows) = await contacts.contacts(account: account) else { return cache[account]?.entries ?? [:] }
        var entries: [String: Entry] = [:]
        for row in rows {
            let entry = Entry(name: row.displayName.isEmpty || row.displayName == row.id ? nil : row.displayName, classification: row.classification)
            entries[row.id] = entry
            if let root = row.rootCommitment, !root.isEmpty { entries[root] = entry }
        }
        cache[account] = (entries, current)
        return entries
    }
}
