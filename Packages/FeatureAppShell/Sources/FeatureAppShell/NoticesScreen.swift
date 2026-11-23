// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign

public struct NoticesScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rfTheme) private var theme
    private let licenses: [DesignFontLicense]

    public init(licenses: [DesignFontLicense] = DesignFontLicenses.load()) {
        self.licenses = licenses
    }

    public var body: some View {
        VStack(spacing: 0) {
            KitPageHeader(
                FeatureAppShellStrings.text("shell.notices.title", locale: locale),
                onBack: { dismiss() },
                tag: "notices-header"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: KitMetrics.rowGap) {
                    ForEach(Array(licenses.enumerated()), id: \.offset) { _, license in
                        VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
                            Text(license.name).rfFont(.body, weight: .semibold).foregroundStyle(theme.text)
                            Text(license.text)
                                .rfFont(.caption)
                                .foregroundStyle(theme.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, KitMetrics.gutter)
                    }
                }
                .padding(.vertical, KitMetrics.gutter)
            }
        }
        .background(theme.bg)
        .shellHidesSystemBar()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("open-source-notices")
    }
}
