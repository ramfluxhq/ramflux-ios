// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum AgentsAction: Equatable, Sendable {
    case appeared, disappeared, retry, loadMore, query(String), mode(AgentsMode), chat(String)
    case draftName(String), draftResponsibility(String), save, confirmSave, delete, confirmDelete, cancelConfirmation
    case unavailable(AgentUnavailable)
}
