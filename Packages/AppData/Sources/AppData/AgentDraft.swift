// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public struct AgentDraft: Equatable, Sendable {
    public var name = ""
    public var goal = ""
    public var issue: AgentDraftIssue? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .nameRequired }
        if name.unicodeScalars.count > 40 || name.utf8.count > 256 { return .nameLimit }
        if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .goalRequired }
        if goal.utf8.count > 256 { return .goalLimit }
        return nil
    }
    public init() {}
}
