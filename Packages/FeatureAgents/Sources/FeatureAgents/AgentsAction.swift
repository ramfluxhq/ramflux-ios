// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum AgentsAction: Equatable, Sendable { case appeared, disappeared, retry, mode(AgentCapability), name(String), goal(String), create }
