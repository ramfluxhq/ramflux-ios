// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

enum CardChipTone: Sendable {
    case neutral, success, danger
}

/// A status chip (spec 3.2): meta text in a tone, radius 4.
struct CardChip: View {
    let text: String
    let tone: CardChipTone
    @Environment(\.rfTheme) private var theme

    var body: some View {
        let colors: (fill: Color, ink: Color) = switch tone {
        case .neutral: (theme.surface, theme.secondary)
        case .success: (theme.success_bg, theme.success)
        case .danger: (theme.danger_bg, theme.danger)
        }
        Text(text)
            .rfFont(.size(theme.size_meta), weight: .medium)
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: theme.radius_chip))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The lifecycle states of spec 3.4 that the card shows above its body: submitting, consumed, closed, superseded, refused
/// and out of sync (with the Resync button). A card with no lifecycle state shows nothing here.
struct CardLifecycleChrome: View {
    let phase: CardPhase
    let closed: Bool
    let outOfSync: Bool
    let onResync: () -> Void
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if phase == .submitting {
                CardChip(text: FeatureCardsStrings.text("cards.chip.submitting", locale: locale), tone: .neutral)
            } else if phase == .consumed {
                CardChip(text: FeatureCardsStrings.text("cards.chip.waiting", locale: locale), tone: .neutral)
            }
            if closed {
                CardChip(text: FeatureCardsStrings.text("cards.chip.closed", locale: locale), tone: .neutral)
                Text(FeatureCardsStrings.text("cards.closed", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            }
            if case .superseded = phase {
                CardChip(text: FeatureCardsStrings.text("cards.chip.updated", locale: locale), tone: .neutral)
                Text(FeatureCardsStrings.text("cards.superseded.title", locale: locale)).rfFont(.size(theme.size_subheading), weight: .semibold)
                    .foregroundStyle(theme.text)
                Text(FeatureCardsStrings.text("cards.superseded.body", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            }
            if case .refused = phase {
                CardChip(text: FeatureCardsStrings.text("cards.chip.refused", locale: locale), tone: .danger)
                Text(FeatureCardsStrings.text("cards.refused.body", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.danger)
            }
            if outOfSync {
                Text(FeatureCardsStrings.text("cards.outOfSync", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                CardActionButton(title: FeatureCardsStrings.text("cards.resync", locale: locale), primary: false, action: onResync)
            }
        }
    }
}
