// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureContacts
@MainActor final class ContactsSnapshotTests: XCTestCase {
    func testContactRequestAndSafetyStates() {
        for (index, state) in ContactsPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(ContactsScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "contacts-\(index)-\(scheme)", scheme: scheme, test: self)
        } }
    }
}
