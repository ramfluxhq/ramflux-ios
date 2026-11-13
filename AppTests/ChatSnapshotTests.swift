// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureChat
@MainActor final class ChatSnapshotTests: XCTestCase {
    func testNativeTimelineAndComposerAcrossMajorStates() {
        for (index, state) in ChatPreviews.states.enumerated() {
            for scheme in [ColorScheme.light, .dark] {
                SnapshotCapture.record(ChatScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "chat-\(index)-\(scheme)", scheme: scheme, test: self)
            }
        }
    }
}
