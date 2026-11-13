// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public struct GroupConfirmation: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let attempt: PendingGroupMutation
    public init(attempt: PendingGroupMutation) { id = UUID(); self.attempt = attempt }
}
