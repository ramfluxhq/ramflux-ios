// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public enum PermissionsAction: Sendable {
    case appeared, foreground, disappeared, accountCreated
    case need(DevicePermission), confirmExplanation, cancelExplanation, explanationDismissed, openSettings, dismissNeeded
}
