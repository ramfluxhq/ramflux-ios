// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Five placeholder rows while the first page loads (board MOB-B01L): a 52 pt circle and two bars.
struct ConversationsSkeleton: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    private static let titleWidths: [CGFloat] = [120, 132, 144, 156, 168]
    private static let previewWidths: [CGFloat] = [200, 190, 180, 170, 160]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.titleWidths.count, id: \.self) { index in
                HStack(spacing: 12) {
                    Circle().fill(theme.surface).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(theme.surface).frame(width: Self.titleWidths[index], height: 14)
                        Capsule().fill(theme.surface).frame(width: Self.previewWidths[index], height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, theme.gap)
                .frame(height: KitMetrics.conversation)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureConversationsStrings.text("conversations.loading", locale: locale))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Centred failure under the search field (board MOB-B01X): icon, title, an optional explanation and
/// a compact outline retry button, kept inside the side margins.
struct ConversationsFailure: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let failure: AppFailure
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            KitIcon(name: failure == .offline ? "wifi-off" : "circle-alert", size: 32, tint: theme.secondary)
                .accessibilityHidden(true)
            Text(failure.title(locale: locale)).rfFont(.size(17), weight: .semibold)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            if failure != .offline {
                Text(failure.message(locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            KitButton(FeatureConversationsStrings.text("conversations.failure.retry", locale: locale), action: retry, kind: .secondary, tag: "conversations-retry")
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, theme.gap)
        .padding(.top, 49)
        .accessibilityElement(children: .contain)
    }
}

/// Centred empty list (board MOB-B12): icon disc, title, explanation and the add-contact action.
struct ConversationsEmpty: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let addContact: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            KitIcon(name: "messages-square", size: 32, tint: theme.secondary)
                .frame(width: 72, height: 72)
                .background(theme.surface, in: Circle())
                .accessibilityHidden(true)
            Text(FeatureConversationsStrings.text("conversations.empty.title", locale: locale)).rfFont(.size(20), weight: .semibold)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            Text(FeatureConversationsStrings.text("conversations.empty.message", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            KitButton(FeatureConversationsStrings.text("conversations.empty.action", locale: locale), action: addContact, tag: "conversations-add-contact")
                .frame(maxWidth: 200)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, theme.gap)
        .padding(.top, 128)
        .accessibilityElement(children: .contain)
    }
}
