// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct TasksState: Equatable, Sendable {
    public var accountID = ""
    public var mode: TasksMode = .conversations
    public var conversations: [ConversationRecord] = []
    public var rows: [TaskRecord] = []
    public var selected: TaskRecord?
    public var permissions: [PermissionRecord] = []
    public var selectedPermission: PermissionRecord?
    public var nextCursor: String?
    public var loading = false
    public var busy = false
    public var fresh = false
    public var failure: AppFailure?
    public var pending: PendingTaskMutation?
    public var confirmation: TaskHostConfirmation?
    public var outcome: TaskMutationOutcome?
    public init(mode: TasksMode = .conversations) { self.mode = mode }
}
