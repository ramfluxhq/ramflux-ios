// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum AgentCapability: String, CaseIterable, Equatable, Sendable {
    case directory, create, profile, advanced, chat, goal, manage, collaboration, edit, remove, pause, hide
}
