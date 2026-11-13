// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ContactsAction: Equatable, Sendable {
    case retryPendingMutation, appeared, disappeared, refresh, mode(ContactsMode), filter(String), principal(String), add
    case requestDecision(String, ContactDecision), confirmDecision, cancelDecision, unavailable(ContactUnavailable)
}
