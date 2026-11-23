// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// What a call media engine can drive on this device. The call screens show a control only
/// when its capability is present.
public struct CallMediaCapabilities: Equatable, Sendable {
    public var audio: Bool
    public var video: Bool
    public var cameraSwitch: Bool
    public var speakerRoute: Bool
    public init(audio: Bool, video: Bool = false, cameraSwitch: Bool = false, speakerRoute: Bool = false) {
        self.audio = audio; self.video = video; self.cameraSwitch = cameraSwitch; self.speakerRoute = speakerRoute
    }
}

/// Whether the engine can carry a call. Invite and answer are sent only while it is available.
public enum CallMediaAvailability: Equatable, Sendable {
    case available(CallMediaCapabilities)
    case unavailable(AppFailure)
    public var capabilities: CallMediaCapabilities? { if case .available(let value) = self { value } else { nil } }
    public var failure: AppFailure? { if case .unavailable(let value) = self { value } else { nil } }
}

public enum CallAudioRoute: String, Equatable, Sendable { case receiver, speaker, bluetooth, wired }

/// A user control applied to the running media session of one call.
public enum CallMediaControl: Equatable, Sendable {
    case mute(Bool)
    case route(CallAudioRoute)
    case camera(Bool)
    case switchCamera
}

public enum CallMediaFailure: String, Equatable, Sendable {
    /// The relay stopped answering; the engine may recover within the lease.
    case relayUnreachable = "relay_unreachable"
    /// The relay refused the token or the peer's frames failed authentication.
    case refused
    /// The microphone, speaker or camera could not be opened.
    case deviceUnavailable = "device_unavailable"
    /// The session material could not be read.
    case invalidMaterial = "invalid_material"
    case unknown
}

public enum CallMediaState: Equatable, Sendable {
    case starting
    case connected
    /// Media stopped flowing; the call is still live in signalling (MOB-K05).
    case reconnecting
    case stopped
    case failed(CallMediaFailure)
}

public enum CallMediaEvent: Equatable, Sendable {
    case state(callID: String, CallMediaState)
    /// Linear levels in 0...1 for the local microphone and the remote stream.
    case audioLevel(callID: String, local: Float, remote: Float)
    case remoteVideo(callID: String, active: Bool)
}

public enum CallVideoSlot: Equatable, Sendable { case local, remote }

/// A platform view the engine renders video into. The call screen owns it and attaches it
/// to a slot; the engine draws into it on the main actor and must not retain it after
/// `attach(nil, ...)` or `stop(callID:)`.
@MainActor public protocol CallVideoSurface: AnyObject {}

/// The one-shot media material of one call: the sealed `call.media.session` completion frame.
///
/// The bytes are the UTF-8 JSON frame `{"code":0,"response":{"ok":true,"body":{...}}}`, where
/// `body` is exactly the SDK's private handoff (see `docs/app-shell.md`, "Call media engine
/// boundary"). The repository checks only the envelope; it never decodes `relay` or `sframe`
/// into Swift values. The engine reads the bytes once inside `consume`, parses them in memory
/// it erases itself, and keeps no other copy. The SDK returns this material exactly once per
/// call: an engine that loses it cannot restart media for that call.
public final class CallMediaSession: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let callID: String
    public let conversationID: String
    public let direction: CallDirection
    private let frame: SecretBytes
    public var description: String { "CallMediaSession" }
    public var debugDescription: String { "CallMediaSession" }
    init(callID: String, conversationID: String, direction: CallDirection, frame: SecretBytes) {
        self.callID = callID; self.conversationID = conversationID; self.direction = direction; self.frame = frame
    }
    /// Reads the material once. The buffer is erased when `use` returns; a second call throws.
    public func consume<T: Sendable>(_ use: (UnsafeRawBufferPointer) throws -> T) throws -> T { try frame.consume(use) }
    /// Erases unread material (an engine that refuses the session calls this).
    public func erase() { frame.erase() }

    /// Checks a sealed `call.media.session` reply without decoding its secret fields and moves
    /// it into a session. The source frame is erased either way.
    static func sealed(_ reply: SecretBytes, call: CallRecord) throws -> CallMediaSession {
        let copy = try reply.consume { bytes -> SecretBytes in
            guard let base = bytes.baseAddress else { throw AppFailure.invalidData }
            // No copy: the decoder reads the erasable buffer in place.
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: bytes.count, deallocator: .none))
            guard envelope.code == 0, envelope.response.ok, envelope.response.body.complete else { throw AppFailure.invalidData }
            return try SecretBytes(copying: bytes)
        }
        return CallMediaSession(callID: call.id, conversationID: call.conversationID, direction: call.direction, frame: copy)
    }
    /// Only presence is decoded: the decoder never builds values for `relay` or `sframe`.
    private struct Envelope: Decodable {
        struct Response: Decodable { let ok: Bool; let body: Body }
        struct Body: Decodable {
            let complete: Bool
            enum Keys: String, CodingKey { case relay, sframe }
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: Keys.self)
                complete = container.contains(.relay) && container.contains(.sframe)
            }
        }
        let code: Int
        let response: Response
    }
}

/// The audio/video engine boundary. The SDK supplies relay signalling and the one-shot session
/// material; an engine supplies capture, Opus/RTP/SFrame, the relay socket and playback. The
/// rf side provides the production engine (request R28); this app ships `RefusingCallMediaEngine`
/// until then. Every method is safe to call for a call the engine does not own (no effect).
public protocol CallMediaEngine: Sendable {
    /// Synchronous and cheap; read before every invite or answer and by the call screens.
    func availability() -> CallMediaAvailability
    /// Takes ownership of the material and starts media for `session.callID`. An engine that
    /// refuses erases the material. The result is final for this call: there is no second read.
    func start(_ session: CallMediaSession) async -> RepositoryResult<Void>
    /// Stops media and releases devices, sockets and key material of the call.
    func stop(callID: String) async
    func control(_ control: CallMediaControl, callID: String) async -> RepositoryResult<Void>
    /// The system audio session was activated or deactivated (by CallKit or an interruption).
    /// Audio I/O may run only while it is active.
    func audioSession(active: Bool) async
    /// A new stream of state, level and video events for every call the engine owns.
    func events() -> AsyncStream<CallMediaEvent>
    /// Attaches (or detaches with nil) the view that shows a slot's video for a call.
    @MainActor func attach(_ surface: (any CallVideoSurface)?, slot: CallVideoSlot, callID: String)
}

/// The engine of this build: there is no audio or video engine a phone can drive yet (R28).
/// It never starts media, so invite and answer are never sent.
public struct RefusingCallMediaEngine: CallMediaEngine {
    public init() {}
    public func availability() -> CallMediaAvailability { .unavailable(.unavailableResource("calls.audioUnavailable")) }
    public func start(_ session: CallMediaSession) async -> RepositoryResult<Void> { session.erase(); return .failure(.unavailableResource("calls.audioUnavailable")) }
    public func stop(callID: String) async {}
    public func control(_ control: CallMediaControl, callID: String) async -> RepositoryResult<Void> { .failure(.unavailableResource("calls.audioUnavailable")) }
    public func audioSession(active: Bool) async {}
    public func events() -> AsyncStream<CallMediaEvent> { AsyncStream { $0.finish() } }
    @MainActor public func attach(_ surface: (any CallVideoSurface)?, slot: CallVideoSlot, callID: String) {}
}

/// Remembers which calls already had their media session read, so the one-shot material is
/// requested at most once per call even when several screens or updates ask for it.
actor CallMediaHandoff {
    private var claimed: [String] = []
    /// True for the first claim of an account's call; false afterwards.
    func claim(account: String, callID: String) -> Bool {
        let key = account + "\u{0}" + callID
        guard !claimed.contains(key) else { return false }
        claimed.append(key); if claimed.count > 256 { claimed.removeFirst(claimed.count - 256) }
        return true
    }
}
