// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct ContactRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let subtitle: String
    public let verified: Bool?
    public init(id: String, displayName: String, subtitle: String, verified: Bool? = nil) {
        self.id = id; self.displayName = displayName; self.subtitle = subtitle; self.verified = verified
    }
}
