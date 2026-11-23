// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
import RFLocalization

/// App-lifetime owner of the system call integration for the active account: observes
/// `call.changed`, keeps the system UI in step, and carries out its actions through the
/// repository. Construct once (one CallKit provider per process) and call `start(account:)`
/// after unlock and `stop()` on lock or account switch.
@MainActor public final class CallSystemService {
    private let repository: any CallsRepository
    public let bridge: CallSystemBridge
    private var observer: Task<Void, Never>?
    private var account: String?
    private var rows: [String: CallRecord] = [:]
    private let audio: CallAudioSession?
    public init(repository: any CallsRepository, provider: any CallSystemProvider, audio: CallAudioSession? = nil, display: @escaping (CallRecord) -> String = { CallDisplay.handle($0) }) {
        self.repository = repository; self.audio = audio
        bridge = CallSystemBridge(provider: provider, availability: { repository.mediaAvailability() }, display: display)
        bridge.onIntent = { [weak self] intent in self?.perform(intent) }
        // An interruption (a cellular call, an alarm) pauses the engine's audio I/O.
        audio?.onEvent = { [weak self] event in
            switch event {
            case .interrupted: self?.perform(.audio(active: false))
            case .interruptionEnded(let resume): if resume { self?.perform(.audio(active: true)) }
            case .routeChanged: break
            }
        }
    }
    public func start(account: String) {
        guard self.account != account || observer == nil else { return }
        stop(); self.account = account
        if bridge.enabled { audio?.startObserving() }
        observer = Task { [weak self, repository] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                if update == .invalidated { await self.refresh(account: account) }
            }
            await observation.stop()
        }
    }
    public func stop() { observer?.cancel(); observer = nil; account = nil; rows = [:]; audio?.stopObserving() }
    /// The app invited a call: show it in the system UI.
    public func outgoingStarted(_ row: CallRecord) async { configureAudio(); rows[row.id] = row; await bridge.outgoingStarted(row) }
    private func configureAudio() {
        #if os(iOS)
        try? audio?.configure(video: false)
        #endif
    }
    private func refresh(account: String) async {
        guard bridge.enabled, case .success(let page) = await repository.history(account: account, cursor: nil), self.account == account else { return }
        for row in page.rows { rows[row.id] = row }
        if page.rows.contains(where: { $0.phase == .incomingRinging }) { configureAudio() }
        await bridge.update(page.rows)
        for row in page.rows where row.phase == .active { _ = await repository.connectMedia(account: account, call: row) }
        for row in page.rows where row.phase == .ended { await repository.stopMedia(callID: row.id); rows[row.id] = nil }
    }
    private func perform(_ intent: CallSystemIntent) {
        guard let account else { return }
        Task { [repository] in
            switch intent {
            case .answer(let id):
                guard let row = rows[id] else { return }
                _ = await repository.signal(account: account, attempt: CallSignalAttempt(expected: row, signal: .answer, operationID: UUID().uuidString))
            case .end(let id):
                guard let row = rows[id], row.canHangup else { return }
                _ = await repository.signal(account: account, attempt: CallSignalAttempt(expected: row, signal: row.canDecline ? .decline : .hangup, operationID: UUID().uuidString))
            case .mute(let id, let muted): _ = await repository.control(.mute(muted), callID: id)
            case .audio(let active): await repository.audioSession(active: active)
            }
        }
    }
    deinit { observer?.cancel() }
}

/// The text the system call UI shows for a call: the peer id as a left-to-right identifier.
public enum CallDisplay {
    public static func handle(_ row: CallRecord) -> String { RFIdentifier.display(row.peerID) }
}
