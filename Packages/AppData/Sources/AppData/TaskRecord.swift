// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct TaskRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let conversationID: String
    public let version: UInt64
    public let title: String
    public let status: String
    public let requester: String?
    public let assignee: String
    public let steps: [TaskStepRecord]
    public let result: String?
    public let pendingResolution: Bool
    public let stalled: Bool
    public init(id: String, conversationID: String, version: UInt64, title: String, status: String, requester: String?, assignee: String, steps: [TaskStepRecord] = [], result: String? = nil, pendingResolution: Bool = false, stalled: Bool = false) {
        self.id = id; self.conversationID = conversationID; self.version = version; self.title = title; self.status = status; self.requester = requester; self.assignee = assignee; self.steps = steps; self.result = result; self.pendingResolution = pendingResolution; self.stalled = stalled
    }
}
