// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct ContactRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let subtitle: String
    public let rootCommitment: String?
    /// Friend link id; `contact.remove`, `contact.block` and `contact.unblock` select the contact by it.
    public let linkID: String?
    public let blocked: Bool
    /// SDK-verified kind; `.aiAgent` shows the AI marker.
    public let classification: PrincipalClassification
    public init(id: String, displayName: String, subtitle: String, rootCommitment: String? = nil, linkID: String? = nil, blocked: Bool = false, classification: PrincipalClassification = .unknown) {
        self.classification = classification
        self.id = id; self.displayName = displayName; self.subtitle = subtitle; self.rootCommitment = rootCommitment
        self.linkID = linkID; self.blocked = blocked
    }
}
