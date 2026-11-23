// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData

/// The app's permission hook: runs the explanation sheet and the system prompt for a device
/// permission and reports whether it is usable. It matches
/// `AppComposition.requestPermission(_:resolved:)`, so the composition conforms without code.
/// Calls request the microphone (and the camera for video) only right before an invite or an
/// answer that the media engine can carry; nothing is requested while the engine refuses.
@MainActor public protocol CallPermissionRequesting: AnyObject {
    func requestPermission(_ permission: DevicePermission, resolved: @escaping @MainActor (Bool) -> Void)
}

/// Display names for peers, resolved in one batch per history read (for example from the
/// contact list). Names are peer-controlled text and are shown through `Text(untrusted:)`.
public protocol CallPeerNames: Sendable {
    func names(account: String, peers: [String]) async -> [String: String]
}
