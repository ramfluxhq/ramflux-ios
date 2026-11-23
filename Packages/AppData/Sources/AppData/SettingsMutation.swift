// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum SettingsMutation: Equatable, Sendable {
    case revoke(DeviceRecord), retention(Int64), setDefault(NodeRecord), lock
    /// `contact.requests.policy.set`: `auto_accept` when true, `manual` otherwise.
    case requestPolicy(autoAccept: Bool)
    /// `account.sign_out`: closes the account on this phone; its code opens it again.
    case signOut
    /// `account.remove_local`: erases the account's data and keys from this phone. Other devices and the
    /// account itself are not affected; the recovery phrase or a backup brings it back.
    case removeLocal
}
