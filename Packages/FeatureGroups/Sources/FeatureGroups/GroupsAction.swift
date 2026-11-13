// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum GroupsAction: Equatable, Sendable {
    case openMessages(String), appeared, disappeared, refresh, filter(String), name(String), mode(GroupsMode)
    case prepareCreate, prepareRename, prepareAdd(String), prepareRole(String, String), prepareRemove(String), prepareInvitation(String, Bool)
    case confirm(UUID), cancelConfirmation, reconcileOriginal(String), unavailable(GroupUnavailable)
}
