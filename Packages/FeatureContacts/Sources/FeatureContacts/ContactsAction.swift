// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ContactsAction: Equatable, Sendable {
    case retryPendingMutation, appeared, disappeared, refresh, loadMore, loadBefore, mode(ContactsMode), filter(String), principal(String), add
    case requestDecision(String, ContactDecision), confirmDecision, cancelDecision, unavailable(ContactUnavailable)
    case requestChange(ContactChange), confirmChange, cancelChange
    /// Identity review of the profile contact: open the sheet, close it ("Not now"), and the explicit accept.
    case identityReview, identityLater, identityAccept(anchor: String)
    /// Sends the contact request for the `@name` that was looked up, only while the field still holds that text.
    case sendUsername
}
