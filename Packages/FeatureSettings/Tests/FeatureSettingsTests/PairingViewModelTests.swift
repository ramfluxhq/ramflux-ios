// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CoreGraphics
import Synchronization
import Testing
import AppData
import RFDesign
private typealias KitQrCodeProbe = KitQrCode
@testable import FeatureSettings

private let operation = PairingOperation(id: "OP", generation: 1)
private func progress(_ phase: PairingPhase, transcript: String? = nil, emoji: [Int]? = nil, proposal: String? = nil, result: String? = nil) -> PairingProgress {
    PairingProgress(operation: operation, phase: phase, expiresAt: .distantFuture, transcriptHash: transcript, emoji: emoji,
                    peerDeviceID: transcript == nil ? nil : "DEV2", peerName: transcript == nil ? nil : "Desk", capabilities: ["message", "sync"], proposalHash: proposal, result: result)
}

private actor PairingFake: PairingRepository {
    var statuses: [RepositoryResult<PairingProgress>]
    var beginResult: RepositoryResult<PairingInvitation>?
    private(set) var invitation: PairingInvitation?
    private(set) var log: [String] = []
    init(statuses: [RepositoryResult<PairingProgress>], expiresAt: Date = .distantFuture) {
        self.statuses = statuses
        let invitation = PairingInvitation(operation: operation, expiresAt: expiresAt, token: Array("TOKEN".utf8))
        self.invitation = invitation; beginResult = .success(invitation)
    }
    func begin(account: String, deviceName: String, operationID: String) -> RepositoryResult<PairingInvitation> { log.append("begin:" + deviceName); return beginResult ?? .failure(.failed) }
    func status(account: String, operation: PairingOperation) -> RepositoryResult<PairingProgress> {
        log.append("status")
        if statuses.count > 1 { return statuses.removeFirst() }
        return statuses.first ?? .failure(.offline)
    }
    func confirm(account: String, shown: PairingProgress, matches: Bool, operationID: String) -> RepositoryResult<PairingProgress> {
        log.append("confirm:\(matches)")
        return .success(matches ? progress(.sasPending, transcript: shown.transcriptHash, emoji: shown.emoji) : progress(.cancelled, result: "SasMismatch"))
    }
    func approve(account: String, reviewed: PairingProgress, approved: Bool, operationID: String) -> RepositoryResult<PairingProgress> {
        log.append("approve:\(approved)")
        return .success(approved ? progress(.prepared, transcript: "TH", proposal: reviewed.proposalHash) : progress(.rejected, result: "WrongRole"))
    }
    func cancel(account: String, operation: PairingOperation, operationID: String) -> RepositoryResult<PairingProgress> { log.append("cancel"); return .success(progress(.cancelled, result: "Expired")) }
    func setStatuses(_ values: [RepositoryResult<PairingProgress>]) { statuses = values }
}

private let image: CGImage = {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    return context!.makeImage()!
}()

@MainActor private func until(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(1)) }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct PairingViewModelTests {
    @Test func fullCeremonyComparesReviewsWithHostConfirmationAndFinishes() async throws {
        let sas = progress(.sasPending, transcript: "TH", emoji: [1, 2, 3, 4, 5, 6, 7])
        let fake = PairingFake(statuses: [.success(progress(.invited)), .success(sas)])
        let renders = Mutex(0)
        let model = PairingViewModel(repository: fake, account: "acc", pollInterval: .milliseconds(1), render: { bytes in renders.withLock { $0 += 1 }; return bytes.count == 5 ? image : nil })
        model.send(.setName("Office Mac")); model.send(.begin)
        await until { if case .invitation = model.state.step { true } else { false } }
        #expect(renders.withLock { $0 } == 1)
        #expect(await fake.invitation?.isErased == true, "token buffer kept after rendering")
        await until { if case .compare = model.state.step { true } else { false } }
        guard case .compare(let shown) = model.state.step else { Issue.record("no comparison"); return }
        #expect(PairingScreen.symbols(shown.emoji ?? []) == "🐱 🦁 🐴 🦄 🐷 🐘 🐰")
        // After confirming, the SDK stays in sas_pending until the peer confirms: the screen waits instead of asking again.
        model.send(.symbolsMatch(true))
        await until { if case .waiting = model.state.step { true } else { false } }
        await fake.setStatuses([.success(progress(.proposalPending, transcript: "TH", proposal: "PH"))])
        await until { if case .review = model.state.step { true } else { false } }
        model.send(.confirmApprove)
        #expect(!(await fake.log.contains("approve:true")), "approved without host confirmation")
        model.send(.requestApprove); #expect(model.state.confirmingApproval)
        await fake.setStatuses([.success(progress(.completed, result: "PublicationPending"))])
        model.send(.confirmApprove)
        await until { if case .finished = model.state.step { true } else { false } }
        guard case .finished(let done) = model.state.step else { Issue.record("not finished"); return }
        #expect(done.phase == .completed && !model.state.confirmingApproval)
        let log = await fake.log
        #expect(log.first == "begin:Office Mac" && log.contains("confirm:true") && log.contains("approve:true") && !log.contains("cancel"))
    }
    @Test func mismatchEndsTheCeremony() async {
        let fake = PairingFake(statuses: [.success(progress(.sasPending, transcript: "TH", emoji: [0, 0, 0, 0, 0, 0, 0]))])
        let model = PairingViewModel(repository: fake, account: "acc", pollInterval: .milliseconds(1), render: { _ in image })
        model.send(.setName("Mac")); model.send(.begin)
        await until { if case .compare = model.state.step { true } else { false } }
        model.send(.symbolsMatch(false))
        await until { if case .finished = model.state.step { true } else { false } }
        guard case .finished(let end) = model.state.step else { Issue.record("not finished"); return }
        #expect(end.result == "SasMismatch" && PairingScreen.finishedBody(end) == "pairing.failure.SasMismatch.body")
    }
    @Test func declineAndCancelAndLeavingTheScreen() async {
        let fake = PairingFake(statuses: [.success(progress(.proposalPending, transcript: "TH", proposal: "PH"))])
        let model = PairingViewModel(repository: fake, account: "acc", pollInterval: .milliseconds(1), render: { _ in image })
        model.send(.setName("Mac")); model.send(.begin)
        await until { if case .review = model.state.step { true } else { false } }
        model.send(.decline)
        await until { if case .finished = model.state.step { true } else { false } }
        #expect(await fake.log.contains("approve:false"))
        model.send(.restart); #expect(model.state.step == .name && model.state.deviceName.isEmpty)

        let waiting = PairingFake(statuses: [.success(progress(.invited))])
        let other = PairingViewModel(repository: waiting, account: "acc", pollInterval: .milliseconds(5), render: { _ in image })
        other.send(.setName("Mac")); other.send(.begin)
        await until { other.state.operation != nil }
        other.send(.covered(true)); #expect(other.state.covered)
        other.send(.disappeared)
        #expect(other.state.step == .name)
        await until { false }
        #expect(await waiting.log.contains("cancel"), "leaving the screen kept the ceremony running")
    }
    @Test func expiryDropsTheCodeAndCancels() async {
        let fake = PairingFake(statuses: [.success(progress(.invited))], expiresAt: Date(timeIntervalSince1970: 100))
        let model = PairingViewModel(repository: fake, account: "acc", pollInterval: .milliseconds(1), now: { Date(timeIntervalSince1970: 200) }, render: { _ in image })
        model.send(.setName("Mac")); model.send(.begin)
        await until { if case .finished = model.state.step { true } else { false } }
        guard case .finished(let end) = model.state.step else { Issue.record("not expired"); return }
        #expect(end.phase == .expired)
        await until { false }
        #expect(await fake.log.contains("cancel"))
    }
    @Test func unrenderableInvitationIsCancelledAndReported() async {
        let fake = PairingFake(statuses: [])
        let model = PairingViewModel(repository: fake, account: "acc", pollInterval: .milliseconds(1), render: { _ in nil })
        model.send(.setName("Mac")); model.send(.begin)
        await until { model.state.failure != nil }
        #expect(model.state.failure == .pairing(.invitationTooLarge) && model.state.step == .name)
        await until { false }
        #expect(await fake.log.contains("cancel")); #expect(await fake.invitation?.isErased == true)
    }
    @Test func anSDKPairingCodeStopsFollowingWhileOfflineKeepsPolling() async {
        let fake = PairingFake(statuses: [.failure(.offline), .failure(.pairing(.notFound))])
        let model = PairingViewModel(repository: fake, account: "acc", pollInterval: .milliseconds(1), render: { _ in image })
        model.send(.setName("Mac")); model.send(.begin)
        await until { if case .stopped = model.state.step { true } else { false } }
        #expect(model.state.step == .stopped(.pairing(.notFound)))
        #expect(await fake.log.filter { $0 == "status" }.count >= 2)
    }
    @Test func theKitRendersAnInvitationSizedCodeAndRefusesAnOversizedOne() {
        let fits = Array(repeating: UInt8(ascii: "a"), count: 1_800).withUnsafeBytes { KitQrCodeProbe.render($0) }
        let tooLarge = Array(repeating: UInt8(ascii: "a"), count: 4_000).withUnsafeBytes { KitQrCodeProbe.render($0) }
        #expect(fits != nil && tooLarge == nil)
    }
    @Test func noAccountNeverBegins() async {
        let fake = PairingFake(statuses: [])
        let model = PairingViewModel(repository: fake, account: nil, render: { _ in image })
        model.send(.setName("Mac")); model.send(.begin)
        await until { false }
        #expect(await fake.log.isEmpty)
    }
}
