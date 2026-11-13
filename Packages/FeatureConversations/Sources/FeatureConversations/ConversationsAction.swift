// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ConversationsAction: Equatable, Sendable { case appeared, disappeared, refresh, queryChanged(String), search, open(String), contacts, strangers }
