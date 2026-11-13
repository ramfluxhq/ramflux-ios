// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
@MainActor final class CallsSettingsRelay {
    var callback: (() -> Void)?
    func handle(_ event: CallsEvent) { if event == .openSystemSettings { callback?() } }
}
