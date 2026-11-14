// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum DevicePermission: String, CaseIterable, Identifiable, Sendable {
    case notifications, microphone, camera, photoAdd, incomingCalls, photoPicker, files, background
    public var id: Self { self }
    public func isUsable(_ status: DevicePermissionStatus) -> Bool {
        status == .allowed || (status == .limited && (self == .notifications || self == .photoAdd))
    }
}
public enum DevicePermissionStatus: String, Sendable { case allowed, limited, restricted, denied, notAsked, notRequired, unavailable }
public struct DevicePermissionsSnapshot: Equatable, Sendable {
    public var values: [DevicePermission: DevicePermissionStatus]
    public init(values: [DevicePermission: DevicePermissionStatus] = [:]) { self.values = values }
    public subscript(_ permission: DevicePermission) -> DevicePermissionStatus { values[permission] ?? .unavailable }
}
public enum DeviceSettingsDestination: Equatable, Sendable { case app, notifications }
/// An opened result means the system accepted the URL, not that the destination was inspected.
public enum DeviceSettingsOpenResult: Equatable, Sendable { case opened, deferred, failed }
/// Device-local OS authority. No SDK call, node upload or account-scoped synchronization.
@MainActor public protocol DevicePermissionsRepository: AnyObject {
    /// Reads system status without requesting authorization or APNs registration.
    func snapshot() async -> DevicePermissionsSnapshot
    func notificationOfferConsumed(accountID: String) -> Bool
    /// Call only after the account's explanation sheet resolves.
    func consumeNotificationOffer(accountID: String)
    func registerForNotificationsIfAuthorized() async
    func request(_ permission: DevicePermission) async -> RepositoryResult<DevicePermissionStatus>
    func openSettings(destination: DeviceSettingsDestination) async -> DeviceSettingsOpenResult
}
