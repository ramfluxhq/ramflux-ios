// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign
import AppData
public struct CardsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: CardsState
    public let onAction: (CardsAction) -> Void
    public init(state: CardsState, onAction: @escaping (CardsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(FeatureCardsStrings.text("cards.title", locale: locale), onBack: { dismiss() }, tag: "cards-header")
            if state.available {
                // Cards have no page of their own: they render where agents send them.
                VStack(spacing: theme.gap) {
                    KitStatusHero(icon: "messages-square", tag: "cards-available-hero")
                    Text(FeatureCardsStrings.text("cards.available.title", locale: locale)).rfFont(.body, weight: .semibold).multilineTextAlignment(.center)
                    Text(FeatureCardsStrings.text("cards.available.message", locale: locale)).rfFont(.body).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, theme.gap)
            } else {
                RFUnavailableView(title: state.failure.title(locale: locale), message: state.failure.message(locale: locale))
                if state.checking { ProgressView(FeatureCardsStrings.text("cards.checking", locale: locale)) }
                Button(FeatureCardsStrings.text("cards.retry", locale: locale)) { onAction(.retry) }.disabled(state.checking)
            }
        }.padding(theme.gap).frame(maxWidth: theme.column_max).frame(maxWidth: .infinity) }.rfHidesNavigationBar()
    }
}
