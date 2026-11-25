// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// Where message delivery stands for an account, as the Settings delivery page shows it.
public enum DeliveryStatus: String, Sendable, Equatable {
    /// No token yet, or not registered yet.
    case pending
    case ready
    /// The build has no `aps-environment` entitlement (for example an unsigned build).
    case notConfigured
    /// Release builds register through the central service, which does not exist yet.
    case waitingForCentre
    /// The node answered that it has no APNs credential.
    case serverNoPush
    /// Apple refused to hand out a token.
    case appleFailed
    case notificationsOff
    /// The node or the network refused for now; the SDK retries by itself.
    case retrying
}
