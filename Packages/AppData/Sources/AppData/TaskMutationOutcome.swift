// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct TaskMutationOutcome: Equatable, Sendable {
    public let taskID: String
    public let pending: Bool
    public init(taskID: String, pending: Bool) { self.taskID = taskID; self.pending = pending }
}
