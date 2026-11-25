// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import Foundation
import CallKit
import Push
import AVFAudio

/// CallKit behind `CallSystemProvider`: one `CXProvider` and one `CXCallController` per
/// process. Calls are not added to the system Recents (the handle is an account identifier,
/// not a phone number), hold is unsupported and there is one call at a time.
@MainActor public final class CallKitProvider: NSObject, CallSystemProvider {
    public var onAction: ((CallSystemAction) -> Bool)?
    private let provider: CXProvider
    private let controller = CXCallController()
    public init(supportsVideo: Bool) {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = supportsVideo
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        // A nil queue delivers delegate callbacks on the main queue.
        provider.setDelegate(self, queue: nil)
    }
    private func update(_ call: CallSystemCall) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: call.handle)
        update.localizedCallerName = call.handle
        update.hasVideo = call.video
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }
    public func reportIncoming(_ call: CallSystemCall) async -> Bool {
        do { try await provider.reportNewIncomingCall(with: call.uuid, update: update(call)); return true }
        catch { let code = (error as NSError).code; PushLog.call.notice("push.call.report.error domain=\((error as NSError).domain, privacy: .public) code=\(code, privacy: .public)"); return false }
    }
    public func startOutgoing(_ call: CallSystemCall) async -> Bool {
        let action = CXStartCallAction(call: call.uuid, handle: CXHandle(type: .generic, value: call.handle))
        action.isVideo = call.video
        do { try await controller.request(CXTransaction(action: action)) } catch { return false }
        provider.reportCall(with: call.uuid, updated: update(call)); return true
    }
    public func reportConnecting(_ uuid: UUID) { provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil) }
    public func reportConnected(_ uuid: UUID) { provider.reportOutgoingCall(with: uuid, connectedAt: nil) }
    public func reportEnded(_ uuid: UUID, reason: CallSystemEndReason) {
        let mapped: CXCallEndedReason = switch reason {
        case .failed: .failed
        case .remoteEnded: .remoteEnded
        case .unanswered: .unanswered
        case .answeredElsewhere: .answeredElsewhere
        case .declinedElsewhere: .declinedElsewhere
        }
        provider.reportCall(with: uuid, endedAt: nil, reason: mapped)
    }
    public func requestEnd(_ uuid: UUID) async -> Bool {
        do { try await controller.request(CXTransaction(action: CXEndCallAction(call: uuid))); return true } catch { return false }
    }
    public func requestMute(_ uuid: UUID, muted: Bool) async -> Bool {
        do { try await controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))); return true } catch { return false }
    }
    /// Delivers an action and fulfils or fails it with the bridge's answer.
    nonisolated fileprivate func settle(_ action: CXAction, _ value: CallSystemAction) {
        let accepted = MainActor.assumeIsolated { onAction?(value) == true }
        if accepted { action.fulfill() } else { action.fail() }
    }
    fileprivate func deliver(_ value: CallSystemAction) { _ = onAction?(value) }
}

extension CallKitProvider: CXProviderDelegate {
    nonisolated public func providerDidReset(_ provider: CXProvider) { MainActor.assumeIsolated { deliver(.reset) } }
    nonisolated public func provider(_ provider: CXProvider, perform action: CXStartCallAction) { action.fulfill() }
    nonisolated public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) { settle(action, .answer(action.callUUID)) }
    nonisolated public func provider(_ provider: CXProvider, perform action: CXEndCallAction) { settle(action, .end(action.callUUID)) }
    nonisolated public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) { settle(action, .mute(action.callUUID, action.isMuted)) }
    nonisolated public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) { settle(action, .hold(action.callUUID, action.isOnHold)) }
    nonisolated public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) { MainActor.assumeIsolated { deliver(.audioActivated) } }
    nonisolated public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) { MainActor.assumeIsolated { deliver(.audioDeactivated) } }
}
#endif
