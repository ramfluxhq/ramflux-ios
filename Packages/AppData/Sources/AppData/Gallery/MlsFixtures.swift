// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_MLS_GALLERY
import Foundation

/// Debug-only fixtures of the MLS direct-chat identity (MLS-GUI common design, section 5.1: F1-1 to F1-10).
///
/// This is a scoped exception to docs/bridge.md ("no fake results or preview fixtures in the product"), like the card
/// gallery: the pinned SDK has no `conversation.security` or `contact.trust.accept_change`, and `NativeCore` refuses to
/// start unless the SDK's method list matches. The code is compiled only with `RAMFLUX_MLS_GALLERY` (Debug), is reached
/// only through the gallery, and is deleted once the pin batch (W) is verified on the real SDK. Names are neutral.
public struct MlsFixture: Identifiable, Sendable {
    /// How the fixture answers `accept`.
    public enum Accept: Sendable { case accept, alreadyHandled, mismatchThenAgain }
    public let id: String
    public let heading: String
    public let expected: String
    public let contact: String
    public let name: String
    public let state: IdentityState
    /// The change the status read names; nil is the "waiting for the new identity" case.
    public let known: IdentityChange?
    /// An event injected after the start (`contact.identity_changed`).
    public let event: (after: Duration, change: IdentityChange)?
    public let security: ConversationSecurity?
    /// A later security answer (`conversation.security` after a re-read).
    public let laterSecurity: (after: Duration, value: ConversationSecurity)?
    /// A `conversation.devices_changed` event after the start; the fake counts the re-reads it causes.
    public let devicesChangedAfter: Duration?
    public let accept: Accept
    public let aiFlag: Bool
}

public enum MlsFixtures {
    private static func change(_ contact: String, _ previous: String, _ next: String, ai: Bool = false) -> IdentityChange {
        IdentityChange(contact: contact, username: contact, previousAnchor: previous, newAnchor: next, aiFlag: ai, seenAt: 1_767_258_000)
    }
    private static let ok2 = ConversationSecurity(state: .ok, epoch: 3, peerDevices: 2)
    private static let ok1 = ConversationSecurity(state: .ok, epoch: 2, peerDevices: 1)
    public static let all: [MlsFixture] = [
        MlsFixture(id: "F1-1", heading: "Ana, first seen", expected: "Neutral line, End-to-end encrypted, 2 devices", contact: "ana", name: "Ana", state: .tofu, known: nil, event: nil, security: ok2, laterSecurity: nil, devicesChangedAfter: nil, accept: .accept, aiFlag: false),
        MlsFixture(id: "F1-2", heading: "Ben, verified", expected: "Verified check", contact: "ben", name: "Ben", state: .verified, known: nil, event: nil, security: ok1, laterSecurity: nil, devicesChangedAfter: nil, accept: .accept, aiFlag: false),
        MlsFixture(id: "F1-3", heading: "Chen, changed (event after 1 s)", expected: "Waiting, then banner, list badge, service line, sheet; accept clears the banner", contact: "chen", name: "Chen", state: .changed, known: nil, event: (.seconds(1), change("chen", "A1", "A2")), security: ok1, laterSecurity: nil, devicesChangedAfter: nil, accept: .accept, aiFlag: false),
        MlsFixture(id: "F1-4", heading: "Chen, send blocked", expected: "Send shows the composer prompt; the message stays as a failed bubble", contact: "chen", name: "Chen", state: .changed, known: change("chen", "A1", "A2"), event: nil, security: ok1, laterSecurity: nil, devicesChangedAfter: nil, accept: .accept, aiFlag: false),
        MlsFixture(id: "F1-5", heading: "Chen, changed again", expected: "First accept: The identity changed again; the sheet shows the latest; second accept succeeds", contact: "chen", name: "Chen", state: .changed, known: change("chen", "A1", "A2"), event: nil, security: ok1, laterSecurity: nil, devicesChangedAfter: nil, accept: .mismatchThenAgain, aiFlag: false),
        MlsFixture(id: "F1-6", heading: "Chen, already handled", expected: "Accept: This change was already handled; the banner clears", contact: "chen", name: "Chen", state: .changed, known: change("chen", "A1", "A2"), event: nil, security: ok1, laterSecurity: nil, devicesChangedAfter: nil, accept: .alreadyHandled, aiFlag: false),
        MlsFixture(id: "F1-7", heading: "Scout (agent), changed", expected: "The sheet shows the AI marker", contact: "scout", name: "Scout", state: .changed, known: change("scout", "S1", "S2", ai: true), event: nil, security: ConversationSecurity(state: .ok, epoch: 1, peerDevices: 1, anyAI: true), laterSecurity: nil, devicesChangedAfter: nil, accept: .accept, aiFlag: true),
        MlsFixture(id: "F1-8", heading: "Ana, pending then re-established", expected: "Setting up encryption, then Encryption was re-established and one service line", contact: "ana", name: "Ana", state: .tofu, known: nil, event: nil, security: ConversationSecurity(state: .pending, epoch: 1, peerDevices: 1), laterSecurity: (.milliseconds(1500), ConversationSecurity(state: .reEstablished, epoch: 4, peerDevices: 1, warning: .forkRecovered)), devicesChangedAfter: .milliseconds(1500), accept: .accept, aiFlag: false),
        MlsFixture(id: "F1-9", heading: "Ana, devices changed", expected: "Silent re-read of the security (the counter increases), no line", contact: "ana", name: "Ana", state: .tofu, known: nil, event: nil, security: ok2, laterSecurity: nil, devicesChangedAfter: .seconds(1), accept: .accept, aiFlag: false),
        MlsFixture(id: "F1-10", heading: "Chen, changed, anchor unknown", expected: "Review disabled and Waiting for the new identity", contact: "chen", name: "Chen", state: .changed, known: nil, event: nil, security: ok1, laterSecurity: nil, devicesChangedAfter: nil, accept: .accept, aiFlag: false),
    ]
}
#endif
