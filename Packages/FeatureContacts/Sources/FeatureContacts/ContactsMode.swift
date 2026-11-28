// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ContactsMode: Equatable, Sendable { case contacts, strangers, sent, add, request(String), profile(String)
    /// This account's own contact card, as a QR code and as text, to hand to a peer.
    case myCard
}
