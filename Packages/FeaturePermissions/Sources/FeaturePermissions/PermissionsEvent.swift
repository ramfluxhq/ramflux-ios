// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
/// `ready`: the permission is usable. `declined`: a flow the app started for it ended without it
/// (explanation cancelled, system prompt denied or failed, settings hint dismissed).
public enum PermissionsEvent: Equatable, Sendable { case ready(DevicePermission), declined(DevicePermission) }
