// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public struct TasksState: Equatable, Sendable {
    public var accountID = ""
    public var mode: TasksMode = .conversations
    /// Bounded windows over paged readers (scale rule 3); rows beyond the window are re-read on scroll.
    public var conversations = RowWindow<ConversationRecord>()
    public var tasks = RowWindow<TaskRecord>()
    public var selected: TaskRecord?
    public var permissions = RowWindow<PermissionRecord>()
    public var selectedPermission: PermissionRecord?
    /// Host-drawn confirmation of an approve or deny decision on a pending approval.
    public var approvalConfirmation: ApprovalConfirmation?
    public var loading = false
    public var busy = false
    public var fresh = false
    public var failure: AppFailure?
    public var pending: PendingTaskMutation?
    public var confirmation: TaskHostConfirmation?
    public var outcome: TaskMutationOutcome?
    public init(mode: TasksMode = .conversations) { self.mode = mode }
}
public struct ApprovalConfirmation: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let approval: PermissionApproval
    public let approve: Bool
}
