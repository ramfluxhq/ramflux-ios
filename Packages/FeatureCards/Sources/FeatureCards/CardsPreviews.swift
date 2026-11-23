// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign
public enum CardsPreviews {
    public static var states: [CardsState] { var available = CardsState(); available.available = true; return [CardsState(), available] }
}
#Preview("Cards unavailable") { RFThemeScope { CardsScreen(state: CardsState(), onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { CardsScreen(state: CardsState(), onAction: { _ in }) }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Available") { RFThemeScope { CardsScreen(state: CardsPreviews.states[1], onAction: { _ in }) } }
#Preview("Expanded") { RFThemeScope { CardsScreen(state: CardsState(), onAction: { _ in }) }.environment(\.locale, Locale(identifier: "en-XA")) }
