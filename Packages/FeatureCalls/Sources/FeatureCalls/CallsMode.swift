// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum CallsMode: Equatable, Sendable { case history, dial(String), detail(String), permissions }
