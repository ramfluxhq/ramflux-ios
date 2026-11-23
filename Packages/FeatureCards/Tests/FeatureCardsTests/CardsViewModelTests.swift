// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureCards
@Suite(.timeLimit(.minutes(1))) @MainActor struct CardsViewModelTests {
    @Test func deferredRuntimeRemainsTypedUnavailableWithoutPretendingToOpenACard() async {
        let model = CardsViewModel(repository: UnavailableCardsRepository()); model.send(.appeared); await model.settle()
        #expect(model.state.failure == .unavailableResource("cards.unavailable")); #expect(!model.state.checking)
        let en = model.state.failure.message(locale: Locale(identifier: "en")), zh = model.state.failure.message(locale: Locale(identifier: "zh-CN")), pseudo = model.state.failure.message(locale: Locale(identifier: "en-XA"))
        #expect(en != zh); #expect(pseudo.count > en.count)
        model.send(.retry); model.send(.disappeared); await model.settle(); #expect(model.state == CardsState())
    }
    @Test func aWorkingRepositoryShowsTheAvailableStateInsteadOfInvalidData() async {
        let model = CardsViewModel(repository: Working()); model.send(.appeared); await model.settle()
        #expect(model.state.available); #expect(!model.state.checking)
    }
    @Test func linkButtonsCarryOnlySafeHttpsDestinations() throws {
        #expect(SurfaceLink.validate("https://example.com/a?b=1").map(SurfaceLink.host) == "example.com")
        #expect(SurfaceLink.validate("HTTPS://Docs.Example.COM./x").map(SurfaceLink.host) == "docs.example.com")
        for refused in ["http://example.com/", "https://user@example.com/", "https://user:pw@example.com/", "https://127.0.0.1/", "https://[::1]/", "https://localhost/",
                        "https://printer.local/", "https://single/", "https://example.com/\u{202E}x", "javascript:alert(1)", "https://" + String(repeating: "a", count: 2050) + ".com/"] {
            #expect(SurfaceLink.validate(refused) == nil, "accepted \(refused)")
        }
        let surface = try SurfaceRecord.decode(Data(#"{"surface_ref":"r","surface_id":"s","conversation_id":"c","version":1,"render_allowed":true,"snapshot":{"dataModel":{"u":"https://example.org/p"},"components":[{"id":"b","component":"Button","child":"t","action":{"functionCall":{"@call":"openUrl","args":{"url":{"@path":"/u"}}}}}]}}"#.utf8))
        if case .button(_, _, .link(let target))? = surface.components["b"]?.kind { #expect(surface.linkURL(target)?.absoluteString == "https://example.org/p") } else { Issue.record("Link button not parsed") }
    }
}
private struct Working: CardsRepository { func availability() async -> RepositoryResult<Void> { .success(()) } }
