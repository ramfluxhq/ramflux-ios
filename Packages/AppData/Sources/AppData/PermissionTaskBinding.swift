// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PermissionTaskBinding: Equatable, Sendable {
    public let conversationID: String
    public let taskID: String
    public let stepID: String
    public let openingRevision: UInt64
    public let requester: String
    public let assignee: String
    public let executorDeviceID: String
    public init(conversationID: String, taskID: String, stepID: String, openingRevision: UInt64, requester: String, assignee: String, executorDeviceID: String) { self.conversationID = conversationID; self.taskID = taskID; self.stepID = stepID; self.openingRevision = openingRevision; self.requester = requester; self.assignee = assignee; self.executorDeviceID = executorDeviceID }
}
