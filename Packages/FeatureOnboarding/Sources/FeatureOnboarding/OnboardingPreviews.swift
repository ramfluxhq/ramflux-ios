// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
public enum OnboardingPreviews {
    public static var states: [OnboardingState] { OnboardingStage.allCases.map { stage in
        var state = OnboardingState(stage: stage)
        state.name = "Preview account"
        state.normalized = try? NodeAddress("example.org/invite")
        state.candidate = NodeRecord(id: "preview-node", origin: "https://example.org", fingerprint: "0123 4567 89ab cdef", publicKey: "preview-key")
        state.positions = [3, 7, 11]
        if stage == .recover { state.metadata = CeremonyMetadata(id: "preview", expiresInMilliseconds: 60_000, anchor: "preview-account-fingerprint") }
        return state
    } }
}
#Preview("Onboarding states") {
    ScrollView { LazyVStack { ForEach(OnboardingPreviews.states, id: \.stage) { state in
        OnboardingScreen(state: state, onAction: { _ in }).frame(width: 390, height: 844)
    } } }
}
