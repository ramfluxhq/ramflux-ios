// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData

/// What the call screen shows for the selected call (boards MOB-K01–K05, K08, K09).
public enum CallStage: Equatable, Sendable {
    case outgoing, incoming, connecting, inCall, connectionLost, ended, failed
}

public struct CallsState: Equatable, Sendable {
    /// History rows kept in memory at most (older pages are dropped from the window).
    public static let window = 2_000
    public var accountID = ""
    public var mode: CallsMode = .history
    public var calls: [CallRecord] = []
    public var visibleCalls: [CallRecord] = []
    public var nextCursor: String?
    public var selected: CallRecord?
    public var names: [String: String] = [:]
    public var microphone: MicrophoneStatus = .unavailable
    public var query = ""
    public var loading = false
    public var busy = false
    public var fresh = false
    public var failure: AppFailure?
    public var pending: CallSignalAttempt?
    /// The engine's answer; invite and answer are offered only while it is available.
    public var media: CallMediaAvailability = RefusingCallMediaEngine().availability()
    public var mediaState: CallMediaState?
    public var muted = false
    public var route: CallAudioRoute = .receiver
    public var camera = false
    public var remoteVideo = false
    /// A device permission the user declined for the action they asked for (MOB-K04).
    public var permissionNeeded: DevicePermission?
    public var audioFailure: AppFailure? { media.failure }
    public var canCall: Bool { media.capabilities?.audio == true }
    public var canDecline: Bool { fresh && selected?.canDecline == true && !busy && pending == nil }
    public var canHangup: Bool { fresh && selected?.canHangup == true && !busy && pending == nil }
    public var canAnswer: Bool { canDecline && canCall }
    public var stage: CallStage? {
        guard let row = selected else { return nil }
        switch row.phase {
        case .outgoingRinging: return .outgoing
        case .incomingRinging: return .incoming
        case .connecting: return .connecting
        case .active:
            if case .failed? = mediaState { return .connectionLost }
            return mediaState == .reconnecting ? .connectionLost : .inCall
        case .ended: return row.endReason == "failed" ? .failed : .ended
        case .unknown: return nil
        }
    }
    public init(mode: CallsMode = .history) { self.mode = mode }
}
