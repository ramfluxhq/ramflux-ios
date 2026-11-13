// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign
import AppData
public struct CardsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: CardsState
    public let onAction: (CardsAction) -> Void
    public init(state: CardsState, onAction: @escaping (CardsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(alignment: .leading, spacing: theme.gap) {
            RFPageHeader(title: FeatureCardsStrings.text("cards.title", locale: locale), subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { EmptyView() })
            RFUnavailableView(title: state.failure.title(locale: locale), message: state.failure.message(locale: locale))
            if state.checking { ProgressView(FeatureCardsStrings.text("cards.checking", locale: locale)) }
            Button(FeatureCardsStrings.text("cards.retry", locale: locale)) { onAction(.retry) }.disabled(state.checking)
        }.padding(theme.gap).frame(maxWidth: theme.column_max).frame(maxWidth: .infinity) }
    }
}
