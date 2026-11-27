// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureCards
@Suite(.timeLimit(.minutes(1))) struct SurfaceLinkTests {
    @Test func linkButtonsCarryOnlySafeHttpsDestinations() throws {
        #expect(SurfaceLink.validate("https://example.com/a?b=1").map(SurfaceLink.host) == "example.com")
        #expect(SurfaceLink.validate("HTTPS://Docs.Example.COM./x").map(SurfaceLink.host) == "docs.example.com")
        for refused in ["http://example.com/", "https://user@example.com/", "https://user:pw@example.com/", "https://127.0.0.1/", "https://[::1]/", "https://localhost/",
                        "https://printer.local/", "https://single/", "https://example.com/\u{202E}x", "javascript:alert(1)", "https://" + String(repeating: "a", count: 2050) + ".com/"] {
            #expect(SurfaceLink.validate(refused) == nil, "accepted \(refused)")
        }
    }
}
