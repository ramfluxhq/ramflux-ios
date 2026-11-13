// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct TaskMutationArguments: Equatable, Sendable {
    public let task: TaskRecord
    public let kind: TaskDecisionKind
    public init(task: TaskRecord, kind: TaskDecisionKind) { self.task = task; self.kind = kind }
}
