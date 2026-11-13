// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct CallsState: Equatable, Sendable {
    public var accountID = ""
    public var mode: CallsMode = .history
    public var calls: [CallRecord] = []
    public var visibleCalls: [CallRecord] = []
    public var selected: CallRecord?
    public var microphone: MicrophoneStatus = .unavailable
    public var query = ""
    public var loading = false
    public var busy = false
    public var fresh = false
    public var failure: AppFailure?
    public var audioFailure: AppFailure?
    public var pending: CallSignalAttempt?
    public var canDecline: Bool { fresh && selected?.canDecline == true && !busy && pending == nil }
    public var canHangup: Bool { fresh && selected?.canHangup == true && !busy && pending == nil }
    public init(mode: CallsMode = .history) { self.mode = mode }
}
