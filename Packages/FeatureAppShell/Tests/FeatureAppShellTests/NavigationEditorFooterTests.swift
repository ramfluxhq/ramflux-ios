// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Testing
@testable import FeatureAppShell

@MainActor
struct NavigationEditorFooterTests {
    private let width: CGFloat = 361

    @Test func labelsThatFitStaySideBySideAtOneButtonHeight() {
        let size = measure(NavigationEditorFooter(spacing: 16) {
            button(idealWidth: 120)
            button(idealWidth: 160)
        })
        #expect(abs(size.height - 48) < 0.5)
    }

    @Test func aLabelWiderThanHalfTheWidthStacksBothButtons() {
        let size = measure(NavigationEditorFooter(spacing: 16) {
            button(idealWidth: 120)
            button(idealWidth: 200)
        })
        #expect(abs(size.height - (48 + 16 + 48)) < 0.5)
    }

    private func button(idealWidth: CGFloat) -> some View {
        Color.clear.frame(idealWidth: idealWidth, maxWidth: .infinity, minHeight: 48, maxHeight: 48)
    }

    private func measure(_ view: some View) -> CGSize {
        #if canImport(UIKit)
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .infinity))
        #else
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .infinity))
        #endif
    }
}
