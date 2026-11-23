// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Foundation
import AppData
import RFDesign
/// Illustrative fixtures for previews and captures only; production repositories never use them.
public enum CallsPreviews {
    static let engine = CallMediaAvailability.available(CallMediaCapabilities(audio: true, video: true, cameraSwitch: true, speakerRoute: true))
    public static var states: [CallsState] {
        let phases: [CallPhase] = [.outgoingRinging, .incomingRinging, .connecting, .active, .ended, .unknown]
        let rows: [CallRecord] = phases.enumerated().map { index, phase -> CallRecord in
            let direction: CallDirection = phase == .incomingRinging ? .incoming : .outgoing
            let reason: String? = phase == .ended ? "completed" : nil
            let answered: Int64? = phase == .ended || phase == .active ? 1_800_000_010 : nil
            let ended: Int64? = phase == .ended ? 1_800_000_071 : nil
            return CallRecord(id: "preview-call-\(index)", conversationID: "preview-conversation", peerID: "preview-peer", direction: direction, phase: phase, endReason: reason, sequence: UInt64(index), createdAt: 1_800_000_000, answeredAt: answered, endedAt: ended)
        }
        let missed = CallRecord(id: "preview-call-missed", conversationID: "preview-conversation", peerID: "preview-peer", direction: .incoming, phase: .ended, endReason: "missed", sequence: 9, createdAt: 1_799_990_000, endedAt: 1_799_990_045)
        let failed = CallRecord(id: "preview-call-failed", conversationID: "preview-conversation", peerID: "preview-peer", direction: .outgoing, phase: .ended, endReason: "failed", failureReason: .relayUnavailable, sequence: 4, createdAt: 1_799_980_000, endedAt: 1_799_980_020)
        var history = CallsState(); history.calls = rows + [missed, failed]; history.visibleCalls = history.calls; history.fresh = true
        history.names = ["preview-peer": "Preview Person"]
        var permission = CallsState(mode: .permissions); permission.microphone = .denied
        var offline = CallsState(mode: .dial("preview-conversation")); offline.media = engine; offline.failure = .offline
        var failure = CallsState(); failure.failure = .invalidData
        var loading = CallsState(); loading.loading = true
        var pending = history; pending.pending = CallSignalAttempt(expected: rows[0], signal: .hangup, operationID: "preview-original-key")
        var dialReady = CallsState(mode: .dial("preview-conversation")); dialReady.media = engine
        let refused = rows.map { row in
            var state = history; state.mode = .detail(row.id); state.selected = row; return state
        }
        func live(_ row: CallRecord, _ change: (inout CallsState) -> Void) -> CallsState {
            var state = history; state.media = engine; state.mode = .detail(row.id); state.selected = row; change(&state); return state
        }
        let inCall = live(rows[3]) { $0.mediaState = .connected; $0.muted = true; $0.route = .speaker }
        let permissionNeeded = live(rows[1]) { $0.permissionNeeded = .microphone }
        let connectionLost = live(rows[3]) { $0.mediaState = .reconnecting }
        let callFailed = live(failed) { _ in }
        return [CallsState(), history, permission, offline, failure, loading, pending, CallsState(mode: .dial("preview-conversation")), dialReady] + refused + [inCall, permissionNeeded, connectionLost, callFailed]
    }
}
#Preview("Calls") { RFThemeScope { CallsScreen(state: CallsPreviews.states[1], onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(CallsPreviews.states.indices, id: \.self) { index in CallsScreen(state: CallsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(CallsPreviews.states.indices, id: \.self) { index in CallsScreen(state: CallsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
#Preview("Arabic") { RFThemeScope { CallsScreen(state: CallsPreviews.states[CallsPreviews.states.count - 4], onAction: { _ in }) }.environment(\.locale, Locale(identifier: "ar")).environment(\.layoutDirection, .rightToLeft) }
