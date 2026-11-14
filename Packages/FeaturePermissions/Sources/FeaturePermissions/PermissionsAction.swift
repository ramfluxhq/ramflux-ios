// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum PermissionsAction: Sendable {
    case appeared, foreground, sceneInactive, disappeared
    case accountCreated(String)
    case need(DevicePermission), confirmExplanation, cancelExplanation, explanationDismissed, openSettings, dismissNeeded
}
