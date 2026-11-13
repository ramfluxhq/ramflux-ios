// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public extension RFTheme {
    static var light: Self { RFDesign.light.registeredTheme }
    static var dark: Self { RFDesign.dark.registeredTheme }
    static func adaptive(_ scheme: ColorScheme) -> Self { scheme == .dark ? .dark : .light }
    var bodyFont: Font { .custom(font, size: size_mobile_body, relativeTo: .body) }
    var captionFont: Font { .custom(font, size: size_mobile_caption, relativeTo: .caption) }
    var pageFont: Font { .custom(font, size: size_page, relativeTo: .title) }
}
public struct RFPage<Content: View>: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack { theme.bg.ignoresSafeArea(); content }
            .font(theme.bodyFont).foregroundStyle(theme.text).tint(theme.primary)
    }
}
public struct RFUnavailableView: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let title: String
    public let message: String
    public init(title: String, message: String) { self.title = title; self.message = message }
    public var body: some View {
        RFPage {
            RFStateBlock(title: title, description: message, kind: .empty, theme: theme) { EmptyView() }
                .frame(maxWidth: theme.column_max)
        }
    }
}

public extension View {
    @ViewBuilder func rfAddressInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

public extension EnvironmentValues {
    @Entry var rfLoadsOnAppear = true
}
