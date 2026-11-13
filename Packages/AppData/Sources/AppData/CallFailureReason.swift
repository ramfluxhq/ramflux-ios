// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum CallFailureReason: String, Equatable, Sendable {
    case authorityUnavailable = "authority_unavailable", authorityRefused = "authority_refused", relayUnavailable = "relay_unavailable", mediaLeaseExpired = "media_lease_expired", daemonRestarted = "daemon_restarted", signalingUnavailable = "signaling_unavailable", unknown
}
