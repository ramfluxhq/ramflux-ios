// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public struct NodeAddress: Sendable, Equatable {
    public let entered: String
    public let origin: String
    public let changed: Bool
    public init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 2048 else { throw AppFailure.invalidInput }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var parts = URLComponents(string: candidate), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil else { throw AppFailure.invalidInput }
        parts.scheme = parts.scheme?.lowercased(); parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        guard let url = parts.url, let host = url.host, !host.isEmpty else { throw AppFailure.invalidInput }
        entered = trimmed; origin = url.absoluteString; changed = trimmed != origin
    }
}
