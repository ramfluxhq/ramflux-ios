// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum TasksMode: Equatable, Sendable { case conversations, list(String), detail(conversation: String, task: String), permissions, permission(String) }
