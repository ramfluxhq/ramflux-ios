// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The username directory trust pin the host provisions in the open configuration (`username_directory`).
/// It is public, independently provisioned configuration; the SDK never learns it from an unverified reply
/// and native clients read no environment variable for it.
public struct UsernameDirectoryPin: Sendable, Equatable {
    public let url: String
    public let id: String
    public let publicKey: String
    public let generation: UInt64
    /// Nil unless every field is present and the address is an HTTPS origin. The SDK validates the rest.
    public init?(url: String, id: String, publicKey: String, generation: UInt64) {
        guard url.hasPrefix("https://"), !id.isEmpty, !publicKey.isEmpty, generation > 0, generation <= 9_007_199_254_740_991 else { return nil }
        self.url = url; self.id = id; self.publicKey = publicKey; self.generation = generation
    }
    var json: JSONValue {
        .object(["url": .string(url), "id": .string(id), "public_key": .string(publicKey), "generation": .unsigned(generation)])
    }
}

/// The SDK diagnostic log (`diag` in the open configuration): bounded rotated NDJSON in `<data root>/diag`.
/// The SDK records typed events only, never message bodies, names, keys or free-text errors.
public struct DiagnosticSettings: Sendable, Equatable {
    public enum Level: String, Sendable { case error, warn, info, debug, trace }
    public enum BuildClass: String, Sendable { case release, beta, realrun }
    public let level: Level
    public let buildClass: BuildClass
    public init(level: Level, buildClass: BuildClass) { self.level = level; self.buildClass = buildClass }
    var json: JSONValue {
        .object(["level": .string(level.rawValue), "process": .string("app"), "build_class": .string(buildClass.rawValue)])
    }
}
