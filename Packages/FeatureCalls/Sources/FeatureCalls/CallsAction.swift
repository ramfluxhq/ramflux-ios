// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum CallsAction: Equatable, Sendable {
    case appeared, disappeared, refresh, filter(String), mode(CallsMode), start, answer, audioControl
    case signal(CallSignal, callID: String, sequence: UInt64), reconcile(String), openSettings, settingsResult(Bool)
}
