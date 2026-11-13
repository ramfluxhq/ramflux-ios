// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData
@testable import FeatureOnboarding
@Suite(.timeLimit(.minutes(1))) @MainActor struct SecureSlotTests {
    @Test func replayableStateHasOnlyOpaqueIDAndHostRevokesRetainedPresentation() throws {
        let bytes = Array("{\"code\":0,\"response\":{\"ok\":true,\"body\":{\"phrase\":\"alpha bravo\"}}}".utf8)
        let frame = try bytes.withUnsafeBytes { try SecretBytes(copying: $0) }
        let display = try RecoveryDisplay(frame), slot = SecureRecoverySlot(), id = UUID()
        var state = OnboardingState(stage: .savePhrase); state.displayID = id; let copy = state
        #expect(!Mirror(reflecting: copy).children.contains { $0.value is RecoveryDisplay })
        slot.install(id: id, display: display); #expect(slot.presentation(for: copy.displayID ?? UUID()) === display)
        slot.revoke(); #expect(slot.presentation(for: id) == nil)
        var called = false; display.withDrawingBytes { _ in called = true }; #expect(!called)
        #expect(copy.displayID == id)
    }
}
