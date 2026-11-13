// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ChatAction: Equatable, Sendable, CustomStringConvertible {
    case callRequested, detailsRequested, appeared, disappeared, conceal, refresh, unavailableAttachment, draftChanged(String), send, retrySameSend, requestDelete(String), cancelDelete, confirmDelete, unavailableRevision
    public var description: String { "ChatAction" }
}
