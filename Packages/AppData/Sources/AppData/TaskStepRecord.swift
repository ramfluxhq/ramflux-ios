// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct TaskStepRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: String
    public let interventionKind: String?
    public init(id: String, title: String, status: String, interventionKind: String? = nil) { self.id = id; self.title = title; self.status = status; self.interventionKind = interventionKind }
}
