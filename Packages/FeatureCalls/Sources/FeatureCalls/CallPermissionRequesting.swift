// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData

/// The app's permission hook: runs the explanation sheet and the system prompt for a device
/// permission and reports whether it is usable. It matches
/// `AppComposition.requestPermission(_:resolved:)`, so the composition conforms without code.
/// Calls request the microphone (and the camera for video) only right before an invite or an
/// answer that the media engine can carry; nothing is requested while the engine refuses.
@MainActor public protocol CallPermissionRequesting: AnyObject {
    func requestPermission(_ permission: DevicePermission, resolved: @escaping @MainActor (Bool) -> Void)
}

/// Display names for peers, resolved in one batch per history read (for example from the
/// contact list). Names are peer-controlled text and are shown through `Text(untrusted:)`.
public protocol CallPeerNames: Sendable {
    func names(account: String, peers: [String]) async -> [String: String]
}

/// Peer names from the accepted contacts: pages `contactsPage` (the repository pages its
/// snapshot off the main actor) in steps of `batch` rows and stops as soon as every requested peer
/// is named. A peer that is not a contact keeps no name and is shown by its identifier.
public struct ContactCallPeerNames: CallPeerNames {
    private let contacts: any ContactsRepository
    private let batch: Int
    public init(contacts: any ContactsRepository, batch: Int = 200) { self.contacts = contacts; self.batch = max(1, batch) }
    public func names(account: String, peers: [String]) async -> [String: String] {
        var wanted = Set(peers), names: [String: String] = [:], cursor: String?
        guard !wanted.isEmpty else { return [:] }
        repeat {
            guard !Task.isCancelled, case .success(let page) = await contacts.contactsPage(account: account, query: "", cursor: cursor, limit: batch) else { break }
            for contact in page.rows where wanted.remove(contact.id) != nil {
                let name = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != contact.id { names[contact.id] = name }
            }
            cursor = page.nextCursor
        } while cursor != nil && !wanted.isEmpty
        return names
    }
}
