// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

/// The AI marker shown next to a participant the SDK verified as an AI agent (`verified_classification`
/// `ai_agent`). It is the only difference between an agent and a person in the interface; a
/// self-declared or unverified kind never shows it.
public struct KitAIMarker: View {
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(tag: String? = nil) { self.tag = tag }
    public var body: some View {
        KitLabel(RFDesignStrings.text("kit.ai.marker"), size: theme.size_meta, weight: .semibold, color: theme.on_agent_av, line: KitMetrics.lineTitle, scales: false)
            .padding(.horizontal, KitMetrics.listBadgePad / 2)
            .background(theme.agent_av, in: RoundedRectangle(cornerRadius: KitMetrics.listBadgeRadius / 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RFDesignStrings.text("kit.ai.marker.accessibility"))
            .kitTag(tag)
    }
}
