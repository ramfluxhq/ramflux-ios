// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// Contact names for direct conversation rows, keyed by root commitment and principal id. One
/// `contact.list` read serves a whole directory page; the map is reused for a short time and read
/// again only when a page asks for a peer the map does not know (a new contact) and the last read is
/// not recent. Runs off the main thread (an actor reached from the repository).
actor DirectConversationTitles {
    private let contacts: any ContactsRepository
    private let now: @Sendable () -> Date
    private var cache: [String: (names: [String: String], read: Date)] = [:]
    static let freshFor: TimeInterval = 60
    static let missRetryAfter: TimeInterval = 5
    init(_ contacts: any ContactsRepository) { self.init(contacts, now: { Date() }) }
    init(_ contacts: any ContactsRepository, now: @escaping @Sendable () -> Date) { self.contacts = contacts; self.now = now }
    func names(account: String, wanted: Set<String>) async -> [String: String] {
        let current = now()
        if let entry = cache[account] {
            let age = current.timeIntervalSince(entry.read)
            let missing = !wanted.isSubset(of: entry.names.keys)
            if age < Self.freshFor && (!missing || age < Self.missRetryAfter) { return entry.names }
        }
        guard case .success(let rows) = await contacts.contacts(account: account) else { return cache[account]?.names ?? [:] }
        var names: [String: String] = [:]
        for row in rows where !row.displayName.isEmpty && row.displayName != row.id {
            names[row.id] = row.displayName
            if let root = row.rootCommitment, !root.isEmpty { names[root] = row.displayName }
        }
        cache[account] = (names, current)
        return names
    }
}
