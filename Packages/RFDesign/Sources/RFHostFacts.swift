// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

/// One host-owned fact on a review surface. Values come from trusted app state.
public struct RFHostFact: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let value: String
    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

/// Review list for a mutation. The host supplies the controls; the card does not decide them.
public struct RFHostFacts<Controls: View>: View {
    @Environment(\.rfTheme) private var theme
    private let title: String
    private let origin: String
    private let facts: [RFHostFact]
    private let controls: Controls

    public init(title: String, origin: String, facts: [RFHostFact], @ViewBuilder controls: () -> Controls) {
        self.title = title
        self.origin = origin
        self.facts = facts
        self.controls = controls()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(title).font(theme.bodyFont.weight(.semibold))
            Text(origin).textSelection(.enabled)
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: theme.gap / 2) {
                    Text(fact.label).font(theme.captionFont).foregroundStyle(theme.secondary)
                    Text(fact.value).textSelection(.enabled)
                }
            }
            controls
        }
        .padding(theme.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
    }
}
