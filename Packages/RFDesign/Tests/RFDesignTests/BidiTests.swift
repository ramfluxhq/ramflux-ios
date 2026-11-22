// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RFLocalization
import SwiftUI
@testable import RFDesign

/// The string rules are tested in RFLocalization (UntrustedTextTests); this covers the SwiftUI mapping.
@Suite(.timeLimit(.minutes(1)))
struct BidiTests {
    @Test func contentDirectionComesFromTheFirstStrongCharacter() {
        #expect(RFBidi.contentDirection(of: "مرحبا، كيف حالك؟") == .rightToLeft)
        #expect(RFBidi.contentDirection(of: "Hello مرحبا") == .leftToRight)
        #expect(RFBidi.contentDirection(of: "שלום world") == .rightToLeft)
        #expect(RFBidi.contentDirection(of: "收到，我会回复。") == .leftToRight)
        #expect(RFBidi.contentDirection(of: "@alice مرحبا") == .rightToLeft)
        #expect(RFBidi.contentDirection(of: "https://example.org/a مرحبا") == .rightToLeft)
        #expect(RFBidi.contentDirection(of: "`let x` سطر") == .rightToLeft)
        #expect(RFBidi.contentDirection(of: "12:30 👍 !") == nil)
    }
}
