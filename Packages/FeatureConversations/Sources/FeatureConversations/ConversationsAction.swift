// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum ConversationsAction: Equatable, Sendable { case appeared, disappeared, refresh, loadMore, loadBefore, localeChanged(Locale), queryChanged(String), search, open(String), contacts, strangers, newConversation, addContact }
