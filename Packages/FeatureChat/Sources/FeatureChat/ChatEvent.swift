// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum ChatEvent: Equatable, Sendable {
    case messageSubmitted(String), navigate(AppRoute)
    /// The chat needs a device permission (camera, add-only Photos). The host runs the shared
    /// explanation flow and answers with `ChatAction.permissionResolved`.
    case requestPermission(DevicePermission)
    /// The user wants to forward a message. The host presents its conversation picker and
    /// answers with `ChatAction.forwardTo`, giving the target's conversation id and, for a group,
    /// its `group_id` (the two can differ for groups created elsewhere).
    case chooseForwardTarget(messageID: String)
}
