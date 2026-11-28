// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RFLocalization
public enum AccountNetworking: String, Sendable, Equatable { case networkingPending = "networking_pending", live }
public struct AccountRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let networking: AccountNetworking?
    public let isLocked: Bool
    public init(id: String, displayName: String, isLocked: Bool, networking: AccountNetworking? = nil) { self.id = id; self.displayName = displayName; self.isLocked = isLocked; self.networking = networking }
}

public extension AccountRecord {
    /// The name the account is shown by: its display name, or "Account" when it has none. Never the raw id.
    func title(locale: Locale = .current) -> String {
        displayName.isEmpty ? AppDataStrings.text("account.unnamed", locale: locale) : displayName
    }
    /// The one-line short id (`xxxx xxxx`) that separates two accounts that share a name.
    var shortID: String { RFIdentifier.shortAccountID(id) }
    /// The first letter of the shown name, for the avatar.
    func initial(locale: Locale = .current) -> String { String(title(locale: locale).prefix(1)).uppercased() }
}
