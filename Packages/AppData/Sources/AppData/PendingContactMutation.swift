// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

public struct PendingContactMutation: Equatable, Sendable {
    public let arguments: ContactMutationArguments
    public let operationID: String
    public init(arguments: ContactMutationArguments, operationID: String) { self.arguments = arguments; self.operationID = operationID }
}
