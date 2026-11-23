// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
#if os(iOS)
import AVFAudio
#endif

public enum CallAudioSessionEvent: Equatable, Sendable {
    case interrupted
    /// The interruption ended; `resume` is true when the system suggests resuming audio.
    case interruptionEnded(resume: Bool)
    case routeChanged(CallAudioRoute)
}

/// Pure mappings from system audio values, testable without a device.
public enum CallAudioMapping {
    /// Maps an output port type (`AVAudioSession.Port.rawValue`) to a call route.
    public static func route(port: String) -> CallAudioRoute {
        switch port {
        case "Speaker": .speaker
        case "BluetoothHFP", "BluetoothA2DPOutput", "BluetoothLE": .bluetooth
        case "Headphones", "USBAudio", "HDMI", "LineOut", "CarAudio", "AirPlay": .wired
        default: .receiver
        }
    }
    /// Maps an interruption notification (type 1 began, 0 ended; option bit 1 = should resume).
    public static func interruption(type: UInt, options: UInt) -> CallAudioSessionEvent? {
        switch type {
        case 1: .interrupted
        case 0: .interruptionEnded(resume: options & 1 == 1)
        default: nil
        }
    }
}

/// The call audio session: play-and-record in voice- or video-chat mode with Bluetooth, the
/// speaker override, and interruption and route-change events. With CallKit the system
/// activates the session (`CallSystemAction.audioActivated`); this type only configures it
/// before a call and never activates it itself.
@MainActor public final class CallAudioSession {
    public var onEvent: ((CallAudioSessionEvent) -> Void)?
    private var observers: [any NSObjectProtocol] = []
    public init() {}
    #if os(iOS)
    public func configure(video: Bool) throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: video ? .videoChat : .voiceChat, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
    }
    public func apply(_ route: CallAudioRoute) throws {
        try AVAudioSession.sharedInstance().overrideOutputAudioPort(route == .speaker ? .speaker : .none)
    }
    public var currentRoute: CallAudioRoute {
        CallAudioMapping.route(port: AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "")
    }
    public func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? UInt.max
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            MainActor.assumeIsolated { if let event = CallAudioMapping.interruption(type: type, options: options) { self?.onEvent?(event) } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.onEvent?(.routeChanged(self.currentRoute)) }
        })
    }
    #else
    public func startObserving() {}
    #endif
    public func stopObserving() { observers.forEach(NotificationCenter.default.removeObserver); observers = [] }
}
