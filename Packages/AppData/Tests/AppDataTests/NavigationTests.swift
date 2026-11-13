// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import AppData
struct NavigationTests {
    @Test func untrustedLinksOnlyNavigateToReadRoutes() throws {
        #expect(AppRoute.parse(try #require(URL(string: "ramflux://conversation/thread"))) == .conversation("thread"))
        #expect(AppRoute.parse(try #require(URL(string: "ramflux://conversation/thread?approve=true"))) == nil)
        #expect(AppRoute.parse(try #require(URL(string: "https://example.org/device/approve"))) == nil)
    }
    @Test func nodeAddressDropsPathsAndRejectsCredentials() throws {
        #expect(try NodeAddress("example.org/team?invite=1#join").origin == "https://example.org")
        #expect(throws: AppFailure.invalidInput) { try NodeAddress("https://name:password@example.org") }
        #expect(throws: AppFailure.invalidInput) { try NodeAddress("http://example.org") }
    }
}
