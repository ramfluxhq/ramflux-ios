// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ChatAction: Equatable, Sendable, CustomStringConvertible {
    case callRequested, appeared, disappeared, conceal, refresh
    case loadOlder, jumpToLatest, displayed(String)
    case draftChanged(String), send, retrySameSend, cancelComposer
    case retryOutbox(String), discardOutbox(String)
    case openActions(String), closeActions
    /// Shows a message's text with system selection (from the message actions); a long press on a bubble opens the actions.
    case selectText(String), closeTextSelection
    case beginReply(String), beginEdit(String), beginReact(String), reactionMode(Bool), chooseReaction(String), removeReaction(String), cancelReaction
    case requestDelete(String, MessageDeleteScope), cancelDelete, confirmDelete
    case detailsRequested, closeDetails, setMuted(Bool), openSafetyNumber
    case mediaTapped(String), revealMedia(String), cancelMedia(String), closePreview, saveToPhotos(String)
    case attachRequested, closeAttach, cameraRequested, attachPicked([PickedMedia])
    case removeDraftItem(Int), draftCaptionChanged(String), sendMediaDraft, cancelMediaDraft, openAlbum(String), closeAlbum
    case openGallery, closeGallery, galleryTab(ChatGalleryState.Tab), galleryMore, clearMediaRequested, clearMediaConfirmed, clearMediaCancelled
    case surfaceInput(surfaceRef: String, pointer: String, value: SurfaceInput), surfaceButton(surfaceRef: String, buttonID: String)
    case shareMedia(String), shareFinished, forwardRequested(String), forwardTo(messageID: String, conversation: String, groupID: String?)
    case permissionResolved(DevicePermission, granted: Bool), photoSaved(Bool)
    public var description: String { "ChatAction" }
}
