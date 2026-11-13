// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public struct BackupRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let state: String
    public let sequence: UInt64
    public let accountID: String?
    public let merge: Bool?
    public let shareURL: URL?
    public init(id: String, kind: String, state: String, sequence: UInt64, accountID: String? = nil, merge: Bool? = nil, shareURL: URL? = nil) {
        self.id = id; self.kind = kind; self.state = state; self.sequence = sequence; self.accountID = accountID; self.merge = merge; self.shareURL = shareURL
    }
}
