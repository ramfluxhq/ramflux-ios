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
/// Device-local OS authority. No SDK call, node upload or account-scoped synchronization.
@MainActor public protocol DevicePermissionsRepository: AnyObject {
    func snapshot() async -> DevicePermissionsSnapshot
    func claimNotificationOffer() -> Bool
    func request(_ permission: DevicePermission) async -> RepositoryResult<DevicePermissionStatus>
    func openSettings() async -> Bool
}
