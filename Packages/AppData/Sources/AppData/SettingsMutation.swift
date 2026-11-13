// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum SettingsMutation: Equatable, Sendable {
    case revoke(DeviceRecord), retention(Int64), manualRequests, setDefault(NodeRecord), lock
}
