// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import FeatureGroups
@MainActor final class GroupsSnapshotTests: XCTestCase {
    func testGroupAuthorityAndMajorStates() {
        for (index, state) in GroupsPreviews.states.enumerated() { for scheme in [ColorScheme.light, .dark] {
            SnapshotCapture.record(GroupsScreen(state: state, onAction: { _ in }).environment(\.colorScheme, scheme), name: "groups-\(index)-\(scheme)", scheme: scheme, test: self)
        } }
    }
}
