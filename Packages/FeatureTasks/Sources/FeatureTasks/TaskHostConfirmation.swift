// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public struct TaskHostConfirmation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let attempt: PendingTaskMutation
    public init(attempt: PendingTaskMutation) { id = UUID(); self.attempt = attempt }
}
