// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Foundation
import AppData
import RFDesign
public enum CallsPreviews {
    public static var states: [CallsState] {
        let phases: [CallPhase] = [.outgoingRinging, .incomingRinging, .connecting, .active, .ended, .unknown]
        let rows: [CallRecord] = phases.enumerated().map { index, phase -> CallRecord in
            let direction: CallDirection = phase == .incomingRinging ? .incoming : .outgoing
            let reason: String? = phase == .ended ? "completed" : nil
            let answered: Int64? = phase == .ended ? 1_800_000_010 : nil
            let ended: Int64? = phase == .ended ? 1_800_000_071 : nil
            return CallRecord(id: "preview-call-\(index)", conversationID: "preview-conversation", peerID: "preview-peer", direction: direction, phase: phase, endReason: reason, sequence: UInt64(index), createdAt: 1_800_000_000, answeredAt: answered, endedAt: ended)
        }
        var history = CallsState(); history.calls = rows; history.visibleCalls = rows; history.fresh = true
        var permission = CallsState(mode: .permissions); permission.microphone = .denied
        var offline = history; offline.failure = .offline; offline.fresh = false
        var failure = CallsState(); failure.failure = .invalidData
        var loading = CallsState(); loading.loading = true
        var pending = history; pending.pending = CallSignalAttempt(expected: rows[0], signal: .hangup, operationID: "preview-original-key")
        return [CallsState(), history, permission, offline, failure, loading, pending, CallsState(mode: .dial("preview-conversation"))] + rows.map { row in
            var state = history; state.mode = .detail(row.id); state.selected = row
            state.audioFailure = UnavailableCallsRepository().audioUnavailable(); return state
        }
    }
}
#Preview("Calls") { RFThemeScope { CallsScreen(state: CallsPreviews.states[1], onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(CallsPreviews.states.indices, id: \.self) { index in CallsScreen(state: CallsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(CallsPreviews.states.indices, id: \.self) { index in CallsScreen(state: CallsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
