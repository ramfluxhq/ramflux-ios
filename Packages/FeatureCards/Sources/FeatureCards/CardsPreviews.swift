// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign
public enum CardsPreviews { public static let states: [CardsState] = [CardsState()] }
#Preview("Cards unavailable") { RFThemeScope { CardsScreen(state: CardsState(), onAction: { _ in }) } }
#Preview("Chinese") { RFThemeScope { CardsScreen(state: CardsState(), onAction: { _ in }) }.environment(\.locale, Locale(identifier: "zh-CN")) }
#Preview("Expanded") { RFThemeScope { CardsScreen(state: CardsState(), onAction: { _ in }) }.environment(\.locale, Locale(identifier: "en-XA")) }
