// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum CallsEvent: Equatable, Sendable {
    case openSystemSettings
    /// This phone invited a call; the host shows it in the system call UI (`CallSystemService.outgoingStarted`).
    case outgoingStarted(CallRecord)
}
