// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public extension RFTheme {
    static var light: Self { RFDesign.light.registeredTheme }
    static var dark: Self { RFDesign.dark.registeredTheme }
    static func adaptive(_ scheme: ColorScheme) -> Self { scheme == .dark ? .dark : .light }
    /// The bundled UI face at the body token size. It is correct for Latin and Simplified Chinese
    /// locales only; screens use `rfFont(.body)`, which also covers every other script.
    var bodyFont: Font { .custom(font, size: size_mobile_body, relativeTo: .body) }
    /// See `bodyFont`; screens use `rfFont(.caption)`.
    var captionFont: Font { .custom(font, size: size_mobile_caption, relativeTo: .caption) }
    /// See `bodyFont`; screens use `rfFont(.page)`.
    var pageFont: Font { .custom(font, size: size_page, relativeTo: .title) }
}

/// Text roles for screen text outside Kit components.
public enum RFTextRole: Sendable {
    case body, caption, page
}

public extension View {
    /// The UI font for a role in the active locale: the bundled face for Latin and Simplified
    /// Chinese locales, the system font (with its own line metrics and the locale's Han forms)
    /// for every other script. Both follow Dynamic Type from the token size.
    func rfFont(_ role: RFTextRole) -> some View { modifier(RFFontModifier(role: role)) }
}

private struct RFFontModifier: ViewModifier {
    var role: RFTextRole
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let (size, style): (CGFloat, Font.TextStyle) = switch role {
        case .body: (theme.size_mobile_body, .body)
        case .caption: (theme.size_mobile_caption, .caption)
        case .page: (theme.size_page, .title)
        }
        if KitTypeface.face(for: .ui, locale: locale).isBundled {
            content.font(.custom(theme.font, size: size, relativeTo: style))
        } else {
            content.font(.system(size: kitScaledSize(size, typeSize)))
        }
    }
}
public struct RFPage<Content: View>: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack { theme.bg.ignoresSafeArea(); content }
            .rfFont(.body).foregroundStyle(theme.text).tint(theme.primary)
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
            RFStatusNote(title: title, message: message, icon: "messages-square")
                .frame(maxWidth: theme.column_max)
        }
    }
}

public extension View {
    @ViewBuilder func rfHidesNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
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
