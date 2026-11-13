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
}
