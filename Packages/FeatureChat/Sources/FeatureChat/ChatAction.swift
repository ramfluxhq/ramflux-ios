// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ChatAction: Equatable, Sendable, CustomStringConvertible {
    case callRequested, detailsRequested, appeared, disappeared, conceal, refresh, unavailableAttachment
    case draftChanged(String), send, retrySameSend, cancelComposer
    case beginReply(String), beginEdit(String), beginReact(String), reactionMode(Bool), chooseReaction(String), removeReaction(String), cancelReaction
    case requestDelete(String, MessageDeleteScope), cancelDelete, confirmDelete
    public var description: String { "ChatAction" }
}
