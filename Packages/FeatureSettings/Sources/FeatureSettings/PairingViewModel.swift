// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CoreGraphics
import Observation
import AppData
import RFDesign

/// Follows one pairing ceremony on the inviting phone. The invitation token is read once from its erasable
/// buffer into the QR image and erased; the image is dropped when the other device joins, the ceremony ends
/// or the screen goes away. Progress is read with `device.pair.status` while the screen is visible (the
/// SDK publishes pairing progress on a separate display topic that the shared event source does not carry).
@Observable @MainActor public final class PairingViewModel {
    public private(set) var state: PairingState
    private let repository: any PairingRepository
    private let pollInterval: Duration
    private let now: @Sendable () -> Date
    private let render: @Sendable (UnsafeRawBufferPointer) -> CGImage?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    /// The transcript this device already confirmed; the SDK stays in `sas_pending` until the other side confirms.
    @ObservationIgnored private var confirmedTranscript: String?
    public init(repository: any PairingRepository, account: String?, pollInterval: Duration = .seconds(2), now: @escaping @Sendable () -> Date = Date.init,
                render: @escaping @Sendable (UnsafeRawBufferPointer) -> CGImage? = KitQrCode.render) {
        self.repository = repository; self.pollInterval = pollInterval; self.now = now; self.render = render; state = PairingState(account: account)
    }
    public func send(_ action: PairingAction) {
        switch action {
        case .appeared: if state.operation != nil { schedulePoll(immediately: true) }
        case .covered(let value): state.covered = value
        case .disappeared: abandon()
        case .setName(let name): if case .name = state.step { state.deviceName = name }
        case .begin: begin()
        case .symbolsMatch(let matches):
            guard case .compare(let shown) = state.step, let account = state.account, !state.busy else { return }
            mutate { [repository] in await repository.confirm(account: account, shown: shown, matches: matches, operationID: UUID().uuidString) }
                success: { [weak self] in if matches { self?.confirmedTranscript = shown.transcriptHash } }
        case .requestApprove: if case .review = state.step, !state.busy { state.confirmingApproval = true }
        case .cancelApprove: state.confirmingApproval = false
        case .confirmApprove, .decline:
            guard case .review(let reviewed) = state.step, let account = state.account, !state.busy else { return }
            let approved = action == .confirmApprove
            if approved && !state.confirmingApproval { return }
            state.confirmingApproval = false
            mutate { [repository] in await repository.approve(account: account, reviewed: reviewed, approved: approved, operationID: UUID().uuidString) }
        case .cancel:
            guard let account = state.account, let operation = state.operation, !state.busy else { if state.operation == nil { reset() }; return }
            if case .invitation = state.step { state.step = .waiting(PairingProgress(operation: operation, phase: .invited, expiresAt: now())) }
            mutate { [repository] in await repository.cancel(account: account, operation: operation, operationID: UUID().uuidString) }
        case .restart, .done: if state.operation == nil, !state.busy { reset() }
        }
    }

    private func begin() {
        guard case .name = state.step, let account = state.account, !state.busy else { return }
        state.busy = true; state.failure = nil; let name = state.deviceName, current = epoch
        work = Task { [weak self, repository, render] in
            let result = await repository.begin(account: account, deviceName: name, operationID: UUID().uuidString)
            guard case .success(let invitation) = result else {
                guard let self, self.epoch == current, case .failure(let failure) = result else { return }
                self.state.busy = false; self.state.failure = failure; return
            }
            // One read of the token into the code, then the buffer is erased: the image is the only copy left.
            let image = invitation.withToken { render($0) }
            invitation.erase()
            guard let self, self.epoch == current, !Task.isCancelled else {
                _ = await repository.cancel(account: account, operation: invitation.operation, operationID: UUID().uuidString); return
            }
            self.state.busy = false
            guard let image else {
                self.state.failure = .pairing(.invitationTooLarge)
                _ = await repository.cancel(account: account, operation: invitation.operation, operationID: UUID().uuidString); return
            }
            self.state.step = .invitation(PairingCodeImage(image: image, operation: invitation.operation, expiresAt: invitation.expiresAt))
            self.schedulePoll(immediately: false)
        }
    }
    private func mutate(_ operation: @escaping @Sendable () async -> RepositoryResult<PairingProgress>, success: @escaping @MainActor () -> Void = {}) {
        state.busy = true; state.failure = nil; let current = epoch
        work = Task { [weak self] in
            let result = await operation()
            guard let self, self.epoch == current, !Task.isCancelled else { return }
            self.state.busy = false
            switch result {
            case .success(let progress): success(); self.apply(progress)
            case .failure(let failure): self.fail(failure)
            }
        }
    }
    /// Moves to the step the SDK's progress calls for. Leaving the invitation step drops the QR image.
    private func apply(_ progress: PairingProgress) {
        guard let operation = state.operation, operation == progress.operation else { return }
        let next: PairingState.Step
        if progress.phase.isTerminal { next = .finished(progress) }
        else if progress.canCompare && progress.transcriptHash != confirmedTranscript { next = .compare(progress) }
        else if progress.canApprove { next = .review(progress) }
        else if progress.phase.awaitsJoiner, case .invitation(let code) = state.step {
            next = now() >= code.expiresAt ? .finished(PairingProgress(operation: operation, phase: .expired, expiresAt: code.expiresAt, result: PairingIssue.expired.rawValue)) : .invitation(code)
        } else { next = .waiting(progress) }
        if case .review(let old) = state.step, case .review(let new) = next, old.proposalHash == new.proposalHash { } else { state.confirmingApproval = false }
        state.step = next
        if case .finished = next { stopPolling(); return }
        schedulePoll(immediately: false)
    }
    private func fail(_ failure: AppFailure) {
        state.failure = failure
        // A pairing code from the SDK means this ceremony cannot continue; connection failures keep polling.
        if case .pairing(let issue) = failure, issue != .busy, issue != .comparisonChanged, issue != .publicationPending, issue != .deviceName {
            stopPolling(); state.step = .stopped(failure); return
        }
        if state.operation != nil { schedulePoll(immediately: false) }
    }
    private func schedulePoll(immediately: Bool) {
        guard let account = state.account, let operation = state.operation else { return }
        poll?.cancel(); let current = epoch, interval = pollInterval
        poll = Task { [weak self, repository] in
            if !immediately { try? await Task.sleep(for: interval) }
            guard !Task.isCancelled, let self, self.epoch == current, !self.state.busy, self.state.operation == operation else { return }
            if case .invitation(let code) = self.state.step, self.now() >= code.expiresAt {
                self.state.step = .finished(PairingProgress(operation: operation, phase: .expired, expiresAt: code.expiresAt, result: PairingIssue.expired.rawValue))
                _ = await repository.cancel(account: account, operation: operation, operationID: UUID().uuidString); return
            }
            let result = await repository.status(account: account, operation: operation)
            guard !Task.isCancelled, self.epoch == current, !self.state.busy else { return }
            switch result {
            case .success(let progress): self.state.failure = nil; self.apply(progress)
            case .failure(let failure): self.fail(failure)
            }
        }
    }
    private func stopPolling() { poll?.cancel(); poll = nil }
    private func reset() {
        epoch &+= 1; stopPolling(); work?.cancel(); confirmedTranscript = nil
        let account = state.account, covered = state.covered
        state = PairingState(account: account); state.covered = covered
    }
    /// Leaving the screen ends a ceremony that is still running: the invitation can no longer be shown.
    private func abandon() {
        if let account = state.account, let operation = state.operation {
            Task { [repository] in _ = await repository.cancel(account: account, operation: operation, operationID: UUID().uuidString) }
        }
        reset()
    }
    public func settle() async { await work?.value; await poll?.value }
    deinit { work?.cancel(); poll?.cancel() }
}
