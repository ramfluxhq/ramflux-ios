// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ContactsMode: Equatable, Sendable { case contacts, strangers, sent, add, request(String), profile(String), safety(String) }
