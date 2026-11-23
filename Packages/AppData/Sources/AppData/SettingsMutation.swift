// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum SettingsMutation: Equatable, Sendable {
    case revoke(DeviceRecord), retention(Int64), setDefault(NodeRecord), lock
    /// `contact.requests.policy.set`: `auto_accept` when true, `manual` otherwise.
    case requestPolicy(autoAccept: Bool)
}
