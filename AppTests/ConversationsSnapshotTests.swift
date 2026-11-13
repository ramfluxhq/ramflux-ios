// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureConversations
@MainActor final class ConversationsSnapshotTests: XCTestCase {
    func testInboxStatesInBothThemes() {
        for (index, state) in ConversationsPreviews.states.enumerated() {
            for scheme in [ColorScheme.light, .dark] {
                SnapshotCapture.record(ConversationsScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "inbox-\(index)-\(scheme)", scheme: scheme, test: self)
            }
        }
    }
}
