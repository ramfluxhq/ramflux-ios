// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct TaskPage: Equatable, Sendable {
    public let rows: [TaskRecord]
    public let nextCursor: String?
    public init(rows: [TaskRecord], nextCursor: String? = nil) { self.rows = rows; self.nextCursor = nextCursor }
}
