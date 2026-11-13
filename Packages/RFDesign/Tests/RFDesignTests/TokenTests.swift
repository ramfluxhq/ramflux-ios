// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
@testable import RFDesign
struct TokenTests {
    @Test func canonicalMobileGeometry() {
        #expect(RFTheme.light.size_mobile_body == 17)
        #expect(RFTheme.light.radius_button == 4)
        #expect(RFTheme.light.radius_card == 8)
        #expect(RFTheme.light.radius_sheet == 12)
        #expect(RFTheme.dark.size_mobile_body == RFTheme.light.size_mobile_body)
    }
}
