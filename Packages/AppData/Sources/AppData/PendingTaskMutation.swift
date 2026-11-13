// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PendingTaskMutation: Equatable, Sendable {
    public let arguments: TaskMutationArguments
    public let operationID: String
    public init(arguments: TaskMutationArguments, operationID: String) { self.arguments = arguments; self.operationID = operationID }
}
