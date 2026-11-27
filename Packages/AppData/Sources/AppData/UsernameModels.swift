// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// The directory state of an account's username (`username.status`).
public enum UsernameState: String, Sendable, Equatable {
    case empty, pending, committed, aborted
}

/// The username status the directory reports. `name` is the claimed name without `@`; `operationID` is the
/// publication the status describes, which a Refresh re-reads.
public struct UsernameStatus: Sendable, Equatable {
    public let state: UsernameState
    public let name: String?
    public let operationID: String?
    public init(state: UsernameState, name: String? = nil, operationID: String? = nil) {
        self.state = state; self.name = name; self.operationID = operationID
    }
    /// Reads the reply of `username.status` or `username.mutate` (submit). An unknown state is invalid data.
    static func parse(_ body: JSONValue) throws -> Self {
        guard let raw = body["state"]?.string, let state = UsernameState(rawValue: raw) else { throw AppFailure.invalidData }
        let name = body["binding"]?["body"]?["name"]?.string
        if let name, name.isEmpty || name.utf8.count > 256 { throw AppFailure.invalidData }
        let operation = body["operation_id"]?.string
        if let operation, operation.isEmpty || operation.utf8.count > 256 { throw AppFailure.invalidData }
        return Self(state: state, name: name, operationID: operation)
    }
}

/// The result of resolving `@name` (`username.resolve`): the root to send a contact request to, and the
/// profile the directory holds for it. `query` is the name that was looked up, with no `@`.
public struct UsernameResolution: Sendable, Equatable {
    public let query: String
    public let principal: String
    public let displayName: String?
    public let bio: String?
    public init(query: String, principal: String, displayName: String? = nil, bio: String? = nil) {
        self.query = query; self.principal = principal; self.displayName = displayName; self.bio = bio
    }
    static func parse(_ body: JSONValue, query: String) throws -> Self {
        guard let principal = body["principal_id"]?.string, !principal.isEmpty else { throw AppFailure.invalidData }
        let displayName = body["profile"]?["body"]?["display_name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let bio = body["profile"]?["body"]?["bio"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        return Self(query: query, principal: principal, displayName: displayName, bio: bio)
    }
}

/// The username name as the typed field holds it, without a leading `@`; nil when it is empty or too long.
public enum UsernameInput {
    public static func name(_ typed: String) -> String? {
        let name = typed.hasPrefix("@") ? String(typed.dropFirst()) : typed
        guard !name.isEmpty, name.utf8.count <= 256 else { return nil }
        return name
    }
}
