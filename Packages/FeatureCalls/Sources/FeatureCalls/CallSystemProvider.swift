// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData

/// One call as the system call UI knows it. `handle` is display text only (no number).
public struct CallSystemCall: Equatable, Sendable {
    public let uuid: UUID
    public let callID: String
    public let handle: String
    public let video: Bool
    public init(uuid: UUID, callID: String, handle: String, video: Bool) { self.uuid = uuid; self.callID = callID; self.handle = handle; self.video = video }
}

public enum CallSystemEndReason: Equatable, Sendable { case failed, remoteEnded, unanswered, answeredElsewhere, declinedElsewhere }

/// User actions from the system call UI (lock screen, Dynamic Island, headset buttons).
public enum CallSystemAction: Equatable, Sendable {
    case answer(UUID), end(UUID), mute(UUID, Bool), hold(UUID, Bool)
    case audioActivated, audioDeactivated, reset
}

/// What the app tells the system call UI for one observed call state change.
public enum CallSystemEffect: Equatable, Sendable {
    case reportIncoming
    case reportConnecting
    case reportConnected
    case reportEnded(CallSystemEndReason)
}

/// The system call integration (CallKit on iOS), behind a protocol so the state mapping is
/// tested with a fake. `onAction` returns whether the action is fulfilled (false fails it).
@MainActor public protocol CallSystemProvider: AnyObject {
    var onAction: ((CallSystemAction) -> Bool)? { get set }
    /// False when the system refuses the call (for example Do Not Disturb or a blocked handle).
    func reportIncoming(_ call: CallSystemCall) async -> Bool
    func startOutgoing(_ call: CallSystemCall) async -> Bool
    func reportConnecting(_ uuid: UUID)
    func reportConnected(_ uuid: UUID)
    func reportEnded(_ uuid: UUID, reason: CallSystemEndReason)
    func requestEnd(_ uuid: UUID) async -> Bool
    func requestMute(_ uuid: UUID, muted: Bool) async -> Bool
}

public enum CallSystemMapping {
    /// The system effects of a call moving from `previous` (nil when first seen) to `row`.
    /// Calls that were already over when first seen are never reported. `endedHere` is true
    /// when this phone ended the call through the system UI, which already knows.
    public static func effects(previous: CallPhase?, row: CallRecord, endedHere: Bool) -> [CallSystemEffect] {
        switch row.phase {
        case .incomingRinging: return previous == nil && row.direction == .incoming ? [.reportIncoming] : []
        case .outgoingRinging, .unknown: return []
        case .connecting: return row.direction == .outgoing && previous != .connecting ? [.reportConnecting] : []
        case .active: return row.direction == .outgoing && previous != .active ? [.reportConnected] : []
        case .ended:
            guard let previous, previous != .ended, !endedHere else { return [] }
            return [.reportEnded(reason(row))]
        }
    }
    public static func reason(_ row: CallRecord) -> CallSystemEndReason {
        switch row.endReason {
        case "answered_elsewhere": .answeredElsewhere
        // An incoming call declined on another of this account's devices.
        case "declined": row.direction == .incoming ? .declinedElsewhere : .remoteEnded
        case "missed", "timeout": .unanswered
        case "completed", "cancelled", "busy": .remoteEnded
        default: .failed
        }
    }
}

/// What the bridge asks the repository to do for a system action.
public enum CallSystemIntent: Equatable, Sendable {
    case answer(callID: String), end(callID: String), mute(callID: String, Bool), audio(active: Bool)
}

/// Keeps the system call UI in step with `call.*` state. It is inert while the media engine
/// refuses: the system UI always offers Answer, and this build cannot answer, so incoming
/// calls are then shown only inside the app (seen and declined there).
@MainActor public final class CallSystemBridge {
    private let provider: any CallSystemProvider
    private let availability: () -> CallMediaAvailability
    private let display: (CallRecord) -> String
    private var phases: [String: CallPhase] = [:]
    private var uuids: [String: UUID] = [:]
    private var endedHere: Set<String> = []
    public var onIntent: ((CallSystemIntent) -> Void)?
    public init(provider: any CallSystemProvider, availability: @escaping () -> CallMediaAvailability, display: @escaping (CallRecord) -> String) {
        self.provider = provider; self.availability = availability; self.display = display
        provider.onAction = { [weak self] action in self?.handle(action) ?? false }
    }
    public var enabled: Bool { availability().capabilities?.audio == true }
    public func uuid(for callID: String) -> UUID? { uuids[callID] }
    /// Applies a fresh history read (newest first). Returns the effects it reported.
    @discardableResult public func update(_ rows: [CallRecord]) async -> [CallSystemEffect] {
        guard enabled else { return [] }
        var reported: [CallSystemEffect] = []
        for row in rows where row.phase != .ended || phases[row.id] != nil {
            let effects = CallSystemMapping.effects(previous: phases[row.id], row: row, endedHere: endedHere.contains(row.id))
            phases[row.id] = row.phase
            let uuid = uuids[row.id] ?? UUID(); uuids[row.id] = uuid
            for effect in effects {
                switch effect {
                case .reportIncoming:
                    if !(await provider.reportIncoming(CallSystemCall(uuid: uuid, callID: row.id, handle: display(row), video: false))) { onIntent?(.end(callID: row.id)) }
                case .reportConnecting: provider.reportConnecting(uuid)
                case .reportConnected: provider.reportConnected(uuid)
                case .reportEnded(let reason): provider.reportEnded(uuid, reason: reason)
                }
                reported.append(effect)
            }
            if row.phase == .ended { phases[row.id] = nil; uuids[row.id] = nil; endedHere.remove(row.id) }
        }
        return reported
    }
    /// Registers an outgoing call the app just invited, so it appears in the system UI.
    public func outgoingStarted(_ row: CallRecord) async {
        guard enabled, uuids[row.id] == nil else { return }
        let uuid = UUID(); uuids[row.id] = uuid; phases[row.id] = row.phase
        _ = await provider.startOutgoing(CallSystemCall(uuid: uuid, callID: row.id, handle: display(row), video: false))
    }
    func handle(_ action: CallSystemAction) -> Bool {
        func call(_ uuid: UUID) -> String? { uuids.first { $0.value == uuid }?.key }
        switch action {
        case .answer(let uuid):
            guard enabled, let id = call(uuid) else { return false }; onIntent?(.answer(callID: id)); return true
        case .end(let uuid):
            guard let id = call(uuid) else { return false }; endedHere.insert(id); onIntent?(.end(callID: id)); return true
        case .mute(let uuid, let muted):
            guard let id = call(uuid) else { return false }; onIntent?(.mute(callID: id, muted)); return true
        // Hold is not supported by the relay media session.
        case .hold: return false
        case .audioActivated: onIntent?(.audio(active: true)); return true
        case .audioDeactivated: onIntent?(.audio(active: false)); return true
        case .reset:
            for id in uuids.keys { onIntent?(.end(callID: id)) }
            phases = [:]; uuids = [:]; endedHere = []; return true
        }
    }
}
