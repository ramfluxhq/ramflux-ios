// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// What the chat timeline knows about one card: the listed surface, its session display, and the state of the last action.
public struct CardMessageState: Equatable, Sendable {
    public let surface: CardSurface
    public var display: CardDisplay?
    public var sending: Bool
    public var failure: AppFailure?
    public init(surface: CardSurface, display: CardDisplay? = nil, sending: Bool = false, failure: AppFailure? = nil) {
        self.surface = surface; self.display = display; self.sending = sending; self.failure = failure
    }
}

/// An agent card in the timeline. Until the native renderer lands, it shows the runtime's sanitised fallback text and
/// the lifecycle notes; it never draws card content itself.
public struct SurfaceCardView: View {
    let card: CardMessageState
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme

    public init(card: CardMessageState) { self.card = card }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(untrusted: fallback).rfFont(.body)
            if card.surface.closed { note("cards.closed") } else if card.surface.outOfSync { note("cards.outOfSync") }
            if card.sending { ProgressView(FeatureCardsStrings.text("cards.sending", locale: locale)).rfFont(.caption) }
            if let failure = card.failure { Text(failure.message(locale: locale)).rfFont(.caption).foregroundStyle(theme.danger) }
        }
        .padding(theme.gap)
        .frame(maxWidth: 320, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_bubble))
        .accessibilityElement(children: .contain)
    }

    private var fallback: String {
        let text = card.display?.fallbackText ?? ""
        return text.isEmpty ? FeatureCardsStrings.text("cards.contentUnavailable", locale: locale) : text
    }

    private func note(_ key: String) -> some View {
        Text(FeatureCardsStrings.text(key, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
    }
}
