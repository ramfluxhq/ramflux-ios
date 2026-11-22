// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ChatAction: Equatable, Sendable, CustomStringConvertible {
    case callRequested, appeared, disappeared, conceal, refresh
    case loadOlder, jumpToLatest, displayed(String)
    case draftChanged(String), send, retrySameSend, cancelComposer
    case retryOutbox(String), discardOutbox(String)
    case openActions(String), closeActions
    case beginReply(String), beginEdit(String), beginReact(String), reactionMode(Bool), chooseReaction(String), removeReaction(String), cancelReaction
    case requestDelete(String, MessageDeleteScope), cancelDelete, confirmDelete
    case detailsRequested, closeDetails, setMuted(Bool), openSafetyNumber
    case mediaTapped(String), revealMedia(String), cancelMedia(String), closePreview, saveToPhotos(String)
    case attachRequested, closeAttach, cameraRequested, attachPicked([PickedMedia]), retryMediaSend, discardMediaSend
    case permissionResolved(DevicePermission, granted: Bool), photoSaved(Bool)
    public var description: String { "ChatAction" }
}
