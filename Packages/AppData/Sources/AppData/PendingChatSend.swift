// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PendingChatSend: Sendable {
    public let operationID: String
    public let text: String
    public let unresolved: Bool
    public let result: RepositoryResult<SendOutcome>?
    public init(operationID: String, text: String, unresolved: Bool, result: RepositoryResult<SendOutcome>?) { self.operationID = operationID; self.text = text; self.unresolved = unresolved; self.result = result }
}
