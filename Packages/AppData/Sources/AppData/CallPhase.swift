// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum CallPhase: String, Equatable, Sendable {
    case outgoingRinging = "outgoing_ringing", incomingRinging = "incoming_ringing", connecting, active, ended, unknown
}
