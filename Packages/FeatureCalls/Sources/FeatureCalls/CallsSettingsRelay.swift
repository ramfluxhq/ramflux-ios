// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor final class CallsSettingsRelay {
    var callback: (() -> Void)?
    var outgoing: ((CallRecord) -> Void)?
    func handle(_ event: CallsEvent) {
        switch event { case .openSystemSettings: callback?(); case .outgoingStarted(let row): outgoing?(row) }
    }
}
