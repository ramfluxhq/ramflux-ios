// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct PermissionsState: Equatable, Sendable {
    public var snapshot = DevicePermissionsSnapshot()
    public var explanation: DevicePermission?
    public var permissionNeeded: DevicePermission?
    public var busy = false
    public var failure: AppFailure?
    public init() {}
}
