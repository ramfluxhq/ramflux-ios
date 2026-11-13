// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public extension EnvironmentValues {
    @Entry var rfTheme = RFTheme.light
}
public struct RFThemeScope<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    public let selection: String
    private let content: Content
    public init(selection: String = "system", @ViewBuilder content: () -> Content) { self.selection = selection; self.content = content() }
    public var body: some View {
        content.environment(\.rfTheme, RFThemeRegistry.resolve(selection, scheme: scheme, increasedContrast: contrast == .increased))
            .preferredColorScheme(selection == "system" ? nil : RFThemeRegistry.themes.first(where: { $0.id == selection }).map { $0.isDark ? .dark : .light })
    }
}
